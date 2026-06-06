import Foundation
import Combine
import AppKit

@MainActor
final class SessionTracker: ObservableObject {
    @Published private(set) var nextReset: Date?
    @Published private(set) var sessionStart: Date?        // from transcripts, for display/fallback
    @Published private(set) var utilization: Double?       // real 5-hour usage %, nil if unknown
    @Published private(set) var weeklyUtilization: Double? // real 7-day usage %
    @Published private(set) var authExpired: Bool = false  // Claude Code login expired
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastChecked: Date = Date()

    private let windowDuration: TimeInterval = 5 * 60 * 60
    private let lookbackDuration: TimeInterval = 12 * 60 * 60
    private let claudeProjectsPath: String
    private var refreshTimer: Timer?

    private static let menuTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        return f
    }()

    var hasActiveSession: Bool {
        guard let reset = nextReset, reset > Date() else { return false }
        if let u = utilization { return u > 0 }   // API is authoritative
        return sessionStart != nil                 // fallback: transcripts say we have a window
    }

    /// The menu bar label: the reset time, tinted by real usage (gray if usage
    /// is unknown). Re-read on each refresh tick so it keeps pace.
    var menuBarImage: NSImage {
        guard hasActiveSession, let reset = nextReset else {
            return MenuBarIcon.render(text: "—", color: MenuBarIcon.neutral)
        }
        let text = Self.menuTimeFormatter.string(from: reset)
        if let u = utilization {
            return MenuBarIcon.render(text: text, color: MenuBarIcon.color(utilization: u))
        }
        return MenuBarIcon.render(text: text, color: MenuBarIcon.neutral)
    }

    init() {
        let env = ProcessInfo.processInfo.environment
        let baseDir: String
        if let custom = env["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            baseDir = (custom as NSString).expandingTildeInPath
        } else {
            baseDir = FileManager.default.homeDirectoryForCurrentUser.path + "/.claude"
        }
        self.claudeProjectsPath = baseDir + "/projects"
        refresh()
        // Usage changes as you work; poll every 5 min (plus on demand / on open).
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { refreshTimer?.invalidate() }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        let path = claudeProjectsPath
        let window = windowDuration
        let lookback = lookbackDuration

        Task {
            // Primary source: Anthropic's usage endpoint (real % + real reset).
            let usage = await UsageService.fetch()
            // Fallback / context: reconstruct the window from local transcripts.
            let start = await Task.detached(priority: .userInitiated) {
                Self.detectActiveSessionStart(at: path, windowDuration: window, lookbackDuration: lookback)
            }.value

            self.utilization = usage.fiveHourUtilization
            self.weeklyUtilization = usage.sevenDayUtilization
            self.authExpired = usage.authExpired
            self.sessionStart = start

            if let apiReset = usage.fiveHourResetsAt {
                self.nextReset = apiReset                                  // authoritative
            } else if let start = start {
                self.nextReset = Self.resetTime(forStart: start, window: window)  // reconstructed
            } else {
                self.nextReset = nil
            }

            self.lastChecked = Date()
            self.isLoading = false
        }
    }

    // MARK: - Transcript fallback (used only when the API is unavailable)

    nonisolated private static func detectActiveSessionStart(
        at path: String,
        windowDuration: TimeInterval,
        lookbackDuration: TimeInterval
    ) -> Date? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return nil }

        let now = Date()
        let lookbackStart = now.addingTimeInterval(-lookbackDuration)

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]

        var prompts: [Date] = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            if let mtime = values?.contentModificationDate, mtime < lookbackStart { continue }

            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8) else { continue }

            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let lineData = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      (obj["type"] as? String) == "user" else { continue }
                if (obj["isSidechain"] as? Bool) == true { continue }
                guard Self.isRealUserPrompt(obj) else { continue }
                guard let tsString = obj["timestamp"] as? String else { continue }
                let parsed = iso.date(from: tsString) ?? isoNoFrac.date(from: tsString)
                guard let ts = parsed, ts >= lookbackStart, ts <= now else { continue }
                prompts.append(ts)
            }
        }

        guard !prompts.isEmpty else { return nil }
        prompts.sort()

        // A new window opens only when a prompt lands at/after the current
        // window's ACTUAL reset (start + 5h rounded up to the hour) — not the
        // raw +5h, or a prompt in the rounded tail (e.g. 10:43 when reset is
        // 11:00) would be mistaken for a fresh window.
        var sessionStart = prompts[0]
        for ts in prompts.dropFirst() where ts >= resetTime(forStart: sessionStart, window: windowDuration) {
            sessionStart = ts
        }
        if now >= resetTime(forStart: sessionStart, window: windowDuration) { return nil }
        return sessionStart
    }

    /// Reconstructed reset: first message + 5h, rounded UP to the top of the
    /// UTC hour. Only used when the live API value isn't available.
    nonisolated private static func resetTime(forStart start: Date, window: TimeInterval) -> Date {
        let exact = start.addingTimeInterval(window)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: exact)
        guard let floorHour = cal.date(from: comps) else { return exact }
        if exact == floorHour { return floorHour }
        return cal.date(byAdding: .hour, value: 1, to: floorHour) ?? exact
    }

    nonisolated private static func isRealUserPrompt(_ obj: [String: Any]) -> Bool {
        guard let message = obj["message"] as? [String: Any] else { return false }
        let content = message["content"]
        if content is String { return true }
        if let arr = content as? [[String: Any]] {
            if let first = arr.first, (first["type"] as? String) == "tool_result" { return false }
            return true
        }
        return false
    }
}
