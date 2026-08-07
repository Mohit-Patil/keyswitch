import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var isRequested: Bool {
        self == .enabled || self == .requiresApproval
    }

    var detail: String {
        switch self {
        case .disabled:
            "KeySwitch opens only when you start it."
        case .enabled:
            "KeySwitch will open automatically when you sign in to your Mac."
        case .requiresApproval:
            "Allow KeySwitch in System Settings → General → Login Items to finish enabling it."
        case .unavailable:
            "Launch at Login is unavailable for this copy of KeySwitch. Move a signed build to Applications and try again."
        }
    }
}

enum LaunchAtLoginService {
    static var currentState: LaunchAtLoginState {
        state(for: SMAppService.mainApp.status)
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp

        if enabled {
            guard service.status != .enabled, service.status != .requiresApproval else {
                return
            }
            try service.register()
        } else {
            guard service.status != .notRegistered, service.status != .notFound else {
                return
            }
            try service.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func state(for status: SMAppService.Status) -> LaunchAtLoginState {
        switch status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }
}
