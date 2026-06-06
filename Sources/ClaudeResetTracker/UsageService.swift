import Foundation

/// Reads Claude Code's real usage from Anthropic's official endpoint — the same
/// mechanism Nimbalyst uses. The OAuth token lives in the macOS Keychain (the
/// item Claude Code itself created); we send it ONLY to api.anthropic.com to
/// read usage, never anywhere else, and never write it to disk.
enum UsageService {
    struct Usage {
        var fiveHourUtilization: Double?   // 0–100, the real "% of 5-hour limit"
        var fiveHourResetsAt: Date?        // authoritative reset instant
        var sevenDayUtilization: Double?   // 0–100
        var authExpired: Bool              // token missing/expired → re-login needed
    }

    private static let keychainServices = ["Claude Code-credentials", "Claude Code"]
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let claudeCodeVersion = "2.1.161"

    /// Read the OAuth access token from the Keychain. Tries both service names
    /// Claude Code has used. Returns nil if not found / unreadable.
    static func readAccessToken() -> String? {
        for service in keychainServices {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            task.arguments = ["find-generic-password", "-s", service, "-w"]
            let out = Pipe()
            task.standardOutput = out
            task.standardError = Pipe()
            do { try task.run() } catch { continue }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oauth = obj["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String,
                  !token.isEmpty
            else { continue }
            return token
        }
        return nil
    }

    static func fetch() async -> Usage {
        guard let token = readAccessToken() else {
            return Usage(fiveHourUtilization: nil, fiveHourResetsAt: nil,
                         sevenDayUtilization: nil, authExpired: true)
        }

        var req = URLRequest(url: usageURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-code/\(claudeCodeVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
                return Usage(fiveHourUtilization: nil, fiveHourResetsAt: nil,
                             sevenDayUtilization: nil, authExpired: true)
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return Usage(fiveHourUtilization: nil, fiveHourResetsAt: nil,
                             sevenDayUtilization: nil, authExpired: false)
            }
            let five = obj["five_hour"] as? [String: Any]
            let seven = obj["seven_day"] as? [String: Any]
            return Usage(
                fiveHourUtilization: (five?["utilization"] as? NSNumber)?.doubleValue,
                fiveHourResetsAt: parseISO(five?["resets_at"] as? String),
                sevenDayUtilization: (seven?["utilization"] as? NSNumber)?.doubleValue,
                authExpired: false
            )
        } catch {
            // Offline or transient error — not an auth problem.
            return Usage(fiveHourUtilization: nil, fiveHourResetsAt: nil,
                         sevenDayUtilization: nil, authExpired: false)
        }
    }

    /// Parse e.g. "2026-06-06T20:00:00.713311+00:00". Microsecond fractions trip
    /// up ISO8601DateFormatter, so strip the fractional part and parse the rest.
    static func parseISO(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        let cleaned = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: cleaned)
    }
}
