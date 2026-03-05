import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false

    /// Loads the current launch-at-login state from ServiceManagement.
    init() {
        refresh()
    }

    /// Registers or unregisters the helper and refreshes the published state.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Keep UI in sync with the system state when registration fails.
        }
        refresh()
    }

    /// Re-reads launch-at-login status from the system service.
    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
