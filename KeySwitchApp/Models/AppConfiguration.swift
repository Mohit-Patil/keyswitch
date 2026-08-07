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

enum ExpandedHUDSize: String, Codable, CaseIterable, Identifiable {
    case compact
    case standard
    case large
    case extraLarge

    static let standardSideLength: CGFloat = 384

    var id: Self { self }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    var sideLength: CGFloat {
        switch self {
        case .compact: 320
        case .standard: Self.standardSideLength
        case .large: 448
        case .extraLarge: 512
        }
    }

    var scale: CGFloat {
        sideLength / Self.standardSideLength
    }
}

enum MenuBarIndicatorSize: String, Codable, CaseIterable, Identifiable {
    case compact
    case standard
    case large
    case extraLarge

    var id: Self { self }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }
}

struct AppConfiguration: Codable, Equatable {
    static let defaultDebugPort = 9348
    static let validDebugPortRange = 1...65_535

    var activationMode: ActivationMode
    var activationShortcut: ActivationShortcut
    var layerAutoExitTimeout: LayerAutoExitTimeout
    var showHUD: Bool
    var hudAppearance: HUDAppearance
    var expandedHUDSize: ExpandedHUDSize
    var showMenuBarAgentStatus: Bool
    var menuBarIndicatorSize: MenuBarIndicatorSize
    var blockUnmappedKeys: Bool
    var lightingBrightness: Double
    var animatedAgentLighting: Bool
    var autoDimTimeout: AutoDimTimeout
    var focusCodexOnSingleTap: Bool
    var hasCompletedFirstRunSetup: Bool
    var debugPort: Int {
        didSet {
            if !Self.isValidDebugPort(debugPort) {
                debugPort = oldValue
            }
        }
    }
    var bindings: [KeyBinding]

    init(
        activationMode: ActivationMode,
        activationShortcut: ActivationShortcut,
        layerAutoExitTimeout: LayerAutoExitTimeout = .threeSeconds,
        showHUD: Bool,
        hudAppearance: HUDAppearance = .system,
        expandedHUDSize: ExpandedHUDSize = .standard,
        showMenuBarAgentStatus: Bool = true,
        menuBarIndicatorSize: MenuBarIndicatorSize = .standard,
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
        self.expandedHUDSize = expandedHUDSize
        self.showMenuBarAgentStatus = showMenuBarAgentStatus
        self.menuBarIndicatorSize = menuBarIndicatorSize
        self.blockUnmappedKeys = blockUnmappedKeys
        self.lightingBrightness = lightingBrightness
        self.animatedAgentLighting = animatedAgentLighting
        self.autoDimTimeout = autoDimTimeout
        self.focusCodexOnSingleTap = focusCodexOnSingleTap
        self.hasCompletedFirstRunSetup = hasCompletedFirstRunSetup
        self.debugPort = Self.validatedDebugPort(debugPort)
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
        expandedHUDSize = try container.decodeIfPresent(
            ExpandedHUDSize.self,
            forKey: .expandedHUDSize
        ) ?? .standard
        showMenuBarAgentStatus = try container.decodeIfPresent(
            Bool.self,
            forKey: .showMenuBarAgentStatus
        ) ?? true
        menuBarIndicatorSize = try container.decodeIfPresent(
            MenuBarIndicatorSize.self,
            forKey: .menuBarIndicatorSize
        ) ?? .standard
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
        let decodedDebugPort: Int?
        do {
            decodedDebugPort = try container.decodeIfPresent(Int.self, forKey: .debugPort)
        } catch {
            decodedDebugPort = nil
        }
        debugPort = Self.validatedDebugPort(decodedDebugPort)
        let decodedBindings = try container.decodeIfPresent([KeyBinding].self, forKey: .bindings) ?? []
        bindings = KeyBinding.mergingDefaults(into: decodedBindings)
    }

    static let `default` = AppConfiguration(
        activationMode: .hold,
        activationShortcut: .standard,
        layerAutoExitTimeout: .threeSeconds,
        showHUD: true,
        hudAppearance: .system,
        expandedHUDSize: .standard,
        showMenuBarAgentStatus: true,
        menuBarIndicatorSize: .standard,
        blockUnmappedKeys: true,
        lightingBrightness: 1,
        animatedAgentLighting: false,
        autoDimTimeout: .threeMinutes,
        focusCodexOnSingleTap: false,
        hasCompletedFirstRunSetup: false,
        debugPort: defaultDebugPort,
        bindings: KeyBinding.defaults
    )

    static func isValidDebugPort(_ port: Int) -> Bool {
        validDebugPortRange.contains(port)
    }

    static func validatedDebugPort(_ port: Int?) -> Int {
        guard let port, isValidDebugPort(port) else {
            return defaultDebugPort
        }
        return port
    }
}
