import SwiftUI
import AppKit

@main
struct ClaudeResetTrackerApp: App {
    @StateObject private var tracker = SessionTracker()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(tracker: tracker)
        } label: {
            Text(tracker.menuBarLabel)
        }
        .menuBarExtraStyle(.window)
    }
}
