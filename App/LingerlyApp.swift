import SwiftUI

/// App entry point that wires the app delegate into SwiftUI.
@main
struct LingerlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Exposes the Settings scene used for the menu bar app.
    var body: some Scene {
        Settings {
            SettingsView(appState: appDelegate.appState)
        }
    }
}
