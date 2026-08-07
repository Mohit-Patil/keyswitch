import Foundation

enum HUDAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum StatusHUDMode: String, Codable, CaseIterable, Identifiable {
    case smart
    case always
    case hidden

    var id: Self { self }

    var title: String {
        switch self {
        case .smart: "Smart"
        case .always: "Always visible"
        case .hidden: "Hidden"
        }
    }

    var helpText: String {
        switch self {
        case .smart:
            "The agent pill appears after meaningful status or connection changes, then hides automatically."
        case .always:
            "The agent pill remains visible whenever the full keyboard layer is closed."
        case .hidden:
            "The agent pill stays hidden. Your activation shortcut still opens the complete HUD."
        }
    }
}

enum StatusHUDHideDelay: Int, Codable, CaseIterable, Identifiable {
    case twoSeconds = 2
    case threeSeconds = 3
    case fiveSeconds = 5
    case tenSeconds = 10

    var id: Self { self }

    var title: String {
        "\(rawValue) seconds"
    }

    var interval: TimeInterval {
        TimeInterval(rawValue)
    }
}

struct AppConfiguration: Codable, Equatable {
    var activationMode: ActivationMode
    var activationShortcut: ActivationShortcut
    var layerAutoExitTimeout: LayerAutoExitTimeout
    var showHUD: Bool
    var hudAppearance: HUDAppearance
    var statusHUDMode: StatusHUDMode
    var statusHUDHideDelay: StatusHUDHideDelay
    var blockUnmappedKeys: Bool
    var lightingBrightness: Double
    var animatedAgentLighting: Bool
    var autoDimTimeout: AutoDimTimeout
    var focusCodexOnSingleTap: Bool
    var hasCompletedFirstRunSetup: Bool
    var debugPort: Int
    var bindings: [KeyBinding]

    init(
        activationMode: ActivationMode,
        activationShortcut: ActivationShortcut,
        layerAutoExitTimeout: LayerAutoExitTimeout = .threeSeconds,
        showHUD: Bool,
        hudAppearance: HUDAppearance = .system,
        statusHUDMode: StatusHUDMode = .smart,
        statusHUDHideDelay: StatusHUDHideDelay = .threeSeconds,
        blockUnmappedKeys: Bool,
        lightingBrightness: Double = 1,
        animatedAgentLighting: Bool = false,
        autoDimTimeout: AutoDimTimeout = .threeMinutes,
        focusCodexOnSingleTap: Bool = false,
        hasCompletedFirstRunSetup: Bool = false,
        debugPort: Int,
        bindings: [KeyBinding]
    ) {
        self.activationMode = activationMode
        self.activationShortcut = activationShortcut
        self.layerAutoExitTimeout = layerAutoExitTimeout
        self.showHUD = showHUD
        self.hudAppearance = hudAppearance
        self.statusHUDMode = statusHUDMode
        self.statusHUDHideDelay = statusHUDHideDelay
        self.blockUnmappedKeys = blockUnmappedKeys
        self.lightingBrightness = lightingBrightness
        self.animatedAgentLighting = animatedAgentLighting
        self.autoDimTimeout = autoDimTimeout
        self.focusCodexOnSingleTap = focusCodexOnSingleTap
        self.hasCompletedFirstRunSetup = hasCompletedFirstRunSetup
        self.debugPort = debugPort
        self.bindings = bindings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activationMode = try container.decodeIfPresent(ActivationMode.self, forKey: .activationMode) ?? .hold

        let decodedShortcut = try container.decodeIfPresent(
            ActivationShortcut.self,
            forKey: .activationShortcut
        )
        activationShortcut = decodedShortcut?.isValid == true ? decodedShortcut! : .standard
        layerAutoExitTimeout = try container.decodeIfPresent(
            LayerAutoExitTimeout.self,
            forKey: .layerAutoExitTimeout
        ) ?? .threeSeconds

        showHUD = try container.decodeIfPresent(Bool.self, forKey: .showHUD) ?? true
        hudAppearance = try container.decodeIfPresent(
            HUDAppearance.self,
            forKey: .hudAppearance
        ) ?? .system
        statusHUDMode = try container.decodeIfPresent(
            StatusHUDMode.self,
            forKey: .statusHUDMode
        ) ?? .smart
        statusHUDHideDelay = try container.decodeIfPresent(
            StatusHUDHideDelay.self,
            forKey: .statusHUDHideDelay
        ) ?? .threeSeconds
        blockUnmappedKeys = try container.decodeIfPresent(Bool.self, forKey: .blockUnmappedKeys) ?? true
        lightingBrightness = min(
            max(try container.decodeIfPresent(Double.self, forKey: .lightingBrightness) ?? 1, 0),
            1
        )
        animatedAgentLighting = try container.decodeIfPresent(
            Bool.self,
            forKey: .animatedAgentLighting
        ) ?? false
        autoDimTimeout = try container.decodeIfPresent(
            AutoDimTimeout.self,
            forKey: .autoDimTimeout
        ) ?? .threeMinutes
        focusCodexOnSingleTap = try container.decodeIfPresent(
            Bool.self,
            forKey: .focusCodexOnSingleTap
        ) ?? false
        hasCompletedFirstRunSetup = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasCompletedFirstRunSetup
        ) ?? false
        debugPort = try container.decodeIfPresent(Int.self, forKey: .debugPort) ?? 9348
        let decodedBindings = try container.decodeIfPresent([KeyBinding].self, forKey: .bindings) ?? []
        bindings = KeyBinding.mergingDefaults(into: decodedBindings)
    }

    static let `default` = AppConfiguration(
        activationMode: .hold,
        activationShortcut: .standard,
        layerAutoExitTimeout: .threeSeconds,
        showHUD: true,
        hudAppearance: .system,
        statusHUDMode: .smart,
        statusHUDHideDelay: .threeSeconds,
        blockUnmappedKeys: true,
        lightingBrightness: 1,
        animatedAgentLighting: false,
        autoDimTimeout: .threeMinutes,
        focusCodexOnSingleTap: false,
        hasCompletedFirstRunSetup: false,
        debugPort: 9348,
        bindings: KeyBinding.defaults
    )
}
