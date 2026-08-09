import CoreGraphics
import Foundation

enum ActivationModifier: String, Codable, CaseIterable, Hashable, Identifiable {
    case function
    case control
    case option
    case shift
    case command

    var id: Self { self }

    var title: String {
        switch self {
        case .function: "Fn"
        case .control: "Control"
        case .option: "Option"
        case .shift: "Shift"
        case .command: "Command"
        }
    }

    var symbol: String {
        switch self {
        case .function: "fn"
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }

    var keyCodes: Set<UInt16> {
        switch self {
        case .function: [63]
        case .control: [59, 62]
        case .option: [58, 61]
        case .shift: [56, 60]
        case .command: [54, 55]
        }
    }

    func isPressed(in flags: CGEventFlags) -> Bool {
        switch self {
        case .function:
            flags.contains(.maskSecondaryFn)
        case .control:
            flags.contains(.maskControl)
        case .option:
            flags.contains(.maskAlternate)
        case .shift:
            flags.contains(.maskShift)
        case .command:
            flags.contains(.maskCommand)
        }
    }
}

struct ActivationShortcut: Codable, Hashable, Identifiable {
    let modifiers: Set<ActivationModifier>

    var id: String {
        orderedModifiers.map(\.rawValue).joined(separator: "-")
    }

    var displayName: String {
        orderedModifiers.map(\.title).joined(separator: " + ")
    }

    var isValid: Bool {
        !modifiers.isEmpty
    }

    var isFunctionOnly: Bool {
        modifiers == [.function]
    }

    static let standard = ActivationShortcut(modifiers: [.function, .control])

    func isPressed(in flags: CGEventFlags) -> Bool {
        isValid && modifiers.allSatisfy { $0.isPressed(in: flags) }
    }

    func contains(keyCode: UInt16) -> Bool {
        modifiers.contains { $0.keyCodes.contains(keyCode) }
    }

    var orderedModifiers: [ActivationModifier] {
        ActivationModifier.allCases.filter(modifiers.contains)
    }
}
