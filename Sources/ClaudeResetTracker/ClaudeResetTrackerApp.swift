import SwiftUI
import AppKit

@main
struct ClaudeResetTrackerApp: App {
    @StateObject private var tracker = SessionTracker()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(tracker: tracker)
        } label: {
            Image(nsImage: tracker.menuBarImage)
        }
        .menuBarExtraStyle(.window)
    }
}
