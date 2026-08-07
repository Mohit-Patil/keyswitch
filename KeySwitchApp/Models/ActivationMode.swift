import Foundation

enum ActivationMode: String, Codable, CaseIterable, Identifiable {
    case hold
    case toggle

    var id: Self { self }

    var title: String {
        switch self {
        case .hold: "Hold shortcut"
        case .toggle: "Toggle shortcut"
        }
    }

    var helpText: String {
        switch self {
        case .hold:
            "The layer stays active only while the activation shortcut is held."
        case .toggle:
            "Press the shortcut once to turn the layer on and again to turn it off."
        }
    }
}

enum LayerAutoExitTimeout: Int, Codable, CaseIterable, Identifiable {
    case twoSeconds = 2
    case threeSeconds = 3
    case fourSeconds = 4
    case fiveSeconds = 5
    case never = 0

    var id: Self { self }

    var title: String {
        switch self {
        case .twoSeconds: "2 seconds"
        case .threeSeconds: "3 seconds"
        case .fourSeconds: "4 seconds"
        case .fiveSeconds: "5 seconds"
        case .never: "Never"
        }
    }

    var interval: TimeInterval? {
        rawValue == 0 ? nil : TimeInterval(rawValue)
    }
}
