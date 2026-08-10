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
    private enum CodingKeys: String, CodingKey {
        case modifiers
        case key
    }

    let modifiers: Set<ActivationModifier>
    let key: PhysicalKey?

    init(modifiers: Set<ActivationModifier>, key: PhysicalKey? = nil) {
        self.modifiers = modifiers
        self.key = Self.supportedKey(key)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modifiers = try container.decodeIfPresent(
            Set<ActivationModifier>.self,
            forKey: .modifiers
        ) ?? []
        key = Self.supportedKey(
            try container.decodeIfPresent(PhysicalKey.self, forKey: .key)
        )
    }

    var id: String {
        let components = orderedModifiers.map(\.rawValue) + (key.map { ["key-\($0.keyCode)"] } ?? [])
        return components.joined(separator: "-")
    }

    var displayName: String {
        let components = orderedModifiers.map(\.title) + (key.map { [$0.displayName] } ?? [])
        return components.joined(separator: " + ")
    }

    var isValid: Bool {
        !modifiers.isEmpty || key != nil
    }

    var isModifierOnly: Bool {
        key == nil && !modifiers.isEmpty
    }

    var isFunctionOnly: Bool {
        key == nil && modifiers == [.function]
    }

    static let standard = ActivationShortcut(modifiers: [.function, .control])

    func isPressed(in flags: CGEventFlags) -> Bool {
        isModifierOnly && modifiersArePressed(in: flags)
    }

    func modifiersArePressed(in flags: CGEventFlags) -> Bool {
        modifiers.allSatisfy { $0.isPressed(in: flags) }
    }

    func modifiersMatchExactly(in flags: CGEventFlags) -> Bool {
        ActivationModifier.allCases.allSatisfy { modifier in
            modifiers.contains(modifier) == modifier.isPressed(in: flags)
        }
    }

    func contains(keyCode: UInt16) -> Bool {
        containsModifier(keyCode: keyCode) || key?.keyCode == keyCode
    }

    func containsModifier(keyCode: UInt16) -> Bool {
        modifiers.contains { $0.keyCodes.contains(keyCode) }
    }

    var orderedModifiers: [ActivationModifier] {
        ActivationModifier.allCases.filter(modifiers.contains)
    }

    private static func supportedKey(_ key: PhysicalKey?) -> PhysicalKey? {
        guard let key,
              !key.isModifier,
              key.keyCode != 63,
              !PhysicalKey.modifierKeyCodes.contains(key.keyCode) else { return nil }
        return key
    }
}
