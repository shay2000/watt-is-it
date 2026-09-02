import ServiceManagement

// SMAppService.mainApp.register() succeeds only when the running bundle is in
// an approved location, typically /Applications. From a build/ folder or a
// mounted DMG it throws, which the caller surfaces as an informative alert.

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    // Treat any OS-tracked registration as registered. In particular a
    // .requiresApproval state must still be toggleable off from the UI,
    // otherwise clicking would only re-register with no way to unregister.
    static var isRegistered: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        default:
            return false
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard !isRegistered else { return }
            _ = try SMAppService.mainApp.register()
        } else {
            guard isRegistered else { return }
            _ = try SMAppService.mainApp.unregister()
        }
    }
}
