import Foundation
import ServiceManagement

// SMAppService.mainApp.register() succeeds only when the running bundle is in
// an approved location, typically /Applications. From a build/ folder or a
// mounted DMG it throws, which the caller surfaces as an informative alert.

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard !isEnabled else { return }
            _ = try SMAppService.mainApp.register()
        } else {
            guard isEnabled else { return }
            _ = try SMAppService.mainApp.unregister()
        }
    }
}
