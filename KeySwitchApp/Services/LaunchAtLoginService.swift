import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case registrationMissing

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
        case .registrationMissing:
            "macOS could not find an existing login-item registration. Keep KeySwitch in Applications, then turn this on to register it again."
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
            .registrationMissing
        @unknown default:
            .registrationMissing
        }
    }
}
