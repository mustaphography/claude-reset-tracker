import SwiftUI

struct MenuBarView: View {
    @ObservedObject var tracker: SessionTracker

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 268)
        .onAppear { tracker.refresh() }
    }

    @ViewBuilder private var header: some View {
        if tracker.hasActiveSession, let reset = tracker.nextReset {
            VStack(alignment: .leading, spacing: 6) {
                Text("Next reset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Self.timeFormatter.string(from: reset))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(headerColor)
                    .shadow(color: .primary.opacity(0.25), radius: 0.5)
                Text(subtitle(reset: reset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let weekly = tracker.weeklyUtilization {
                    Text("Weekly limit: \(Int(weekly.rounded()))% used")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else if tracker.authExpired {
            VStack(alignment: .leading, spacing: 6) {
                Text("Usage unavailable")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("Claude Code login expired. Run `claude` and sign in, then click Refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("No active window")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("Send a message in Claude Code to start the 5-hour window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var headerColor: Color {
        if let u = tracker.utilization {
            return Color(nsColor: MenuBarIcon.color(utilization: u))
        }
        return .primary
    }

    private func subtitle(reset: Date) -> String {
        let mins = max(0, Int(reset.timeIntervalSince(Date()) / 60))
        let remaining = mins >= 60 ? "resets in \(mins / 60)h \(mins % 60)m" : "resets in \(mins)m"
        if let u = tracker.utilization {
            return "\(Int(u.rounded()))% of 5-hour limit · \(remaining)"
        }
        return remaining  // usage unknown (offline) — still show the countdown
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                tracker.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .opacity(tracker.isLoading ? 0.5 : 1)
            .disabled(tracker.isLoading)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .font(.caption)
    }
}
