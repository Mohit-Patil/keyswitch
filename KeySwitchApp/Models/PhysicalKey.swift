import AppKit
import Foundation

struct PhysicalKey: Codable, Hashable, Identifiable {
    let keyCode: UInt16
    let displayName: String
    let isModifier: Bool

    var id: String { "\(keyCode)-\(isModifier)" }

    static func from(event: NSEvent) -> PhysicalKey? {
        let code = event.keyCode
        guard code != 63 else { return nil }
        return PhysicalKey(
            keyCode: code,
            displayName: displayName(for: code, characters: event.charactersIgnoringModifiers),
            isModifier: modifierKeyCodes.contains(code)
        )
    }

    static func from(event: CGEvent) -> PhysicalKey? {
        guard let event = NSEvent(cgEvent: event) else { return nil }
        return from(event: event)
    }

    static func displayName(for keyCode: UInt16, characters: String? = nil) -> String {
        if let special = specialKeyNames[keyCode] {
            return special
        }

        if let characters,
           let first = characters.first,
           !first.isWhitespace,
           !first.isNewline {
            return String(first).uppercased()
        }

        return "Key \(keyCode)"
    }

    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62]

    private static let specialKeyNames: [UInt16: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        50: "Backtick",
        51: "Delete",
        53: "Escape",
        54: "Right Command",
        55: "Left Command",
        56: "Left Shift",
        57: "Caps Lock",
        58: "Left Option",
        59: "Left Control",
        60: "Right Shift",
        61: "Right Option",
        62: "Right Control",
        64: "F17",
        65: "Keypad .",
        67: "Keypad *",
        69: "Keypad +",
        71: "Clear",
        75: "Keypad /",
        76: "Enter",
        78: "Keypad -",
        79: "F18",
        80: "F19",
        81: "Keypad =",
        82: "Keypad 0",
        83: "Keypad 1",
        84: "Keypad 2",
        85: "Keypad 3",
        86: "Keypad 4",
        87: "Keypad 5",
        88: "Keypad 6",
        89: "Keypad 7",
        90: "F20",
        91: "Keypad 8",
        92: "Keypad 9",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        105: "F13",
        106: "F16",
        107: "F14",
        109: "F10",
        111: "F12",
        113: "F15",
        114: "Help",
        115: "Home",
        116: "Page Up",
        117: "Forward Delete",
        118: "F4",
        119: "End",
        120: "F2",
        121: "Page Down",
        122: "F1",
        123: "Left Arrow",
        124: "Right Arrow",
        125: "Down Arrow",
        126: "Up Arrow",
    ]

    static let one = PhysicalKey(keyCode: 18, displayName: "1", isModifier: false)
    static let two = PhysicalKey(keyCode: 19, displayName: "2", isModifier: false)
    static let three = PhysicalKey(keyCode: 20, displayName: "3", isModifier: false)
    static let four = PhysicalKey(keyCode: 21, displayName: "4", isModifier: false)
    static let five = PhysicalKey(keyCode: 23, displayName: "5", isModifier: false)
    static let six = PhysicalKey(keyCode: 22, displayName: "6", isModifier: false)
    static let q = PhysicalKey(keyCode: 12, displayName: "Q", isModifier: false)
    static let w = PhysicalKey(keyCode: 13, displayName: "W", isModifier: false)
    static let e = PhysicalKey(keyCode: 14, displayName: "E", isModifier: false)
    static let r = PhysicalKey(keyCode: 15, displayName: "R", isModifier: false)
    static let t = PhysicalKey(keyCode: 17, displayName: "T", isModifier: false)
    static let y = PhysicalKey(keyCode: 16, displayName: "Y", isModifier: false)
    static let a = PhysicalKey(keyCode: 0, displayName: "A", isModifier: false)
    static let s = PhysicalKey(keyCode: 1, displayName: "S", isModifier: false)
    static let d = PhysicalKey(keyCode: 2, displayName: "D", isModifier: false)
    static let f = PhysicalKey(keyCode: 3, displayName: "F", isModifier: false)
    static let g = PhysicalKey(keyCode: 5, displayName: "G", isModifier: false)
    static let h = PhysicalKey(keyCode: 4, displayName: "H", isModifier: false)
    static let i = PhysicalKey(keyCode: 34, displayName: "I", isModifier: false)
    static let j = PhysicalKey(keyCode: 38, displayName: "J", isModifier: false)
    static let k = PhysicalKey(keyCode: 40, displayName: "K", isModifier: false)
    static let l = PhysicalKey(keyCode: 37, displayName: "L", isModifier: false)
    static let tab = PhysicalKey(keyCode: 48, displayName: "Tab", isModifier: false)
    static let space = PhysicalKey(keyCode: 49, displayName: "Space", isModifier: false)
    static let backtick = PhysicalKey(keyCode: 50, displayName: "Backtick", isModifier: false)
    static let capsLock = PhysicalKey(keyCode: 57, displayName: "Caps Lock", isModifier: true)
    static let leftShift = PhysicalKey(keyCode: 56, displayName: "Left Shift", isModifier: true)
    static let rightCommand = PhysicalKey(keyCode: 54, displayName: "Right Command", isModifier: true)
    static let leftArrow = PhysicalKey(keyCode: 123, displayName: "Left Arrow", isModifier: false)
    static let rightArrow = PhysicalKey(keyCode: 124, displayName: "Right Arrow", isModifier: false)
    static let downArrow = PhysicalKey(keyCode: 125, displayName: "Down Arrow", isModifier: false)
    static let upArrow = PhysicalKey(keyCode: 126, displayName: "Up Arrow", isModifier: false)
}
