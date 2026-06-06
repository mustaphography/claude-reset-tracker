import Foundation
import Combine

@MainActor
final class SessionTracker: ObservableObject {
    @Published private(set) var sessionStart: Date?
    @Published private(set) var nextReset: Date?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastChecked: Date = Date()

    private let windowDuration: TimeInterval = 5 * 60 * 60
    private let lookbackDuration: TimeInterval = 12 * 60 * 60
    private let claudeProjectsPath: String
    private var refreshTimer: Timer?

    var hasActiveSession: Bool {
        guard let nextReset = nextReset else { return false }
        return nextReset > Date()
    }

    var menuBarLabel: String {
        guard hasActiveSession, let reset = nextReset else {
            return "Claude –:––"
        }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        return "↻ " + f.string(from: reset)
    }

    init() {
        // Honor a custom config location if the user set one; otherwise ~/.claude.
        // (GUI launches don't inherit shell env, so this mainly helps terminal launches.)
        let env = ProcessInfo.processInfo.environment
        let baseDir: String
        if let custom = env["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            baseDir = (custom as NSString).expandingTildeInPath
        } else {
            baseDir = FileManager.default.homeDirectoryForCurrentUser.path + "/.claude"
        }
        self.claudeProjectsPath = baseDir + "/projects"
        refresh()
        scheduleAutoRefresh()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    private func scheduleAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        let path = claudeProjectsPath
        let window = windowDuration
        let lookback = lookbackDuration

        Task.detached(priority: .userInitiated) {
            let start = Self.detectActiveSessionStart(
                at: path,
                windowDuration: window,
                lookbackDuration: lookback
            )
            await MainActor.run {
                self.sessionStart = start
                if let start = start {
                    self.nextReset = Self.resetTime(forStart: start, window: window)
                } else {
                    self.nextReset = nil
                }
                self.lastChecked = Date()
                self.isLoading = false
            }
        }
    }

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

                // Subagent (sidechain) prompts are spawned by a main-thread
                // prompt that already counts; skip them so a background agent
                // can't be mistaken for the window's opening message.
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

        // Walk forward; a prompt at or after sessionStart + 5h opens a new session.
        var sessionStart = prompts[0]
        for ts in prompts.dropFirst() {
            if ts >= sessionStart.addingTimeInterval(windowDuration) {
                sessionStart = ts
            }
        }

        // If the latest session has already expired, report no active session.
        if now >= sessionStart.addingTimeInterval(windowDuration) {
            return nil
        }
        return sessionStart
    }

    /// Claude's usage window resets at the top of the hour: the reset is the
    /// first message time + 5h, rounded UP to the next whole hour.
    /// e.g. first message 5:39 PM → exact 10:39 PM → reset 11:00 PM.
    ///
    /// Anthropic never rounds the reset *down* (that would grant free quota by
    /// opening a new window early), so the only valid hour-aligned rounding is
    /// up. Hour boundaries are anchored to UTC server-side, so we ceil in UTC
    /// and let the view format the resulting instant in the user's local time.
    /// This matters only for sub-hour timezone offsets (e.g. UTC+5:30); for
    /// whole-hour zones UTC and local rounding are identical.
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
            if let first = arr.first, (first["type"] as? String) == "tool_result" {
                return false
            }
            return true
        }
        return false
    }
}
