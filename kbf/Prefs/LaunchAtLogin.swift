import ServiceManagement

/// Launch-at-login via the modern `SMAppService` (macOS 13+).
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("kbf: launch-at-login change failed: \(error.localizedDescription)")
        }
    }
}
