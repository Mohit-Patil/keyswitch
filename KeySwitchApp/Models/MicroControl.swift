import Foundation

enum MicroControl: String, Codable, CaseIterable, Hashable, Identifiable {
    case agent0
    case agent1
    case agent2
    case agent3
    case agent4
    case agent5
    case fastMode
    case approve
    case reject
    case fork
    case pushToTalk
    case pushToTalkSecondary
    case submit
    case stickUp
    case stickRight
    case stickDown
    case stickLeft
    case dialPrevious
    case dialNext
    case dialPress

    enum InteractionKind {
        case momentary
        case step
    }

    var id: Self { self }

    var microKey: String {
        switch self {
        case .agent0: "AG00"
        case .agent1: "AG01"
        case .agent2: "AG02"
        case .agent3: "AG03"
        case .agent4: "AG04"
        case .agent5: "AG05"
        case .fastMode: "ACT06"
        case .approve: "ACT07"
        case .reject: "ACT08"
        case .fork: "ACT09"
        case .pushToTalk: "ACT10"
        case .pushToTalkSecondary: "ACT11"
        case .submit: "ACT12"
        case .stickUp: "STICK_UP"
        case .stickRight: "STICK_RIGHT"
        case .stickDown: "STICK_DOWN"
        case .stickLeft: "STICK_LEFT"
        case .dialPrevious: "DIAL_PREVIOUS"
        case .dialNext: "DIAL_NEXT"
        case .dialPress: "DIAL_PRESS"
        }
    }

    var interactionKind: InteractionKind {
        switch self {
        case .dialPrevious, .dialNext: .step
        default: .momentary
        }
    }

    /// The hardware event name expected by Codex for the virtual encoder.
    /// Counter-clockwise maps to ArrowDown in Codex's composer-navigation
    /// mode, which advances to the next item.
    var codexEncoderKey: String? {
        switch self {
        case .dialPrevious: "ENC_CW"
        case .dialNext: "ENC_CC"
        case .dialPress: "ENC_PRESS"
        default: nil
        }
    }

    /// Codex joystick angles are normalized turns: right = 0, down = 0.25,
    /// left = 0.5, and up = 0.75.
    var codexJoystickAngle: Double? {
        switch self {
        case .stickRight: 0
        case .stickDown: 0.25
        case .stickLeft: 0.5
        case .stickUp: 0.75
        default: nil
        }
    }

    var slot: Int? {
        switch self {
        case .agent0: 0
        case .agent1: 1
        case .agent2: 2
        case .agent3: 3
        case .agent4: 4
        case .agent5: 5
        default: nil
        }
    }

    var title: String {
        switch self {
        case .agent0: "Agent 1"
        case .agent1: "Agent 2"
        case .agent2: "Agent 3"
        case .agent3: "Agent 4"
        case .agent4: "Agent 5"
        case .agent5: "Agent 6"
        case .fastMode: "Fast mode"
        case .approve: "Approve"
        case .reject: "Reject"
        case .fork: "Fork"
        case .pushToTalk: "Push to talk"
        case .pushToTalkSecondary: "Microphone key 2"
        case .submit: "Codex / Submit"
        case .stickUp: "Stick up"
        case .stickRight: "Stick right"
        case .stickDown: "Stick down"
        case .stickLeft: "Stick left"
        case .dialPrevious: "Dial previous"
        case .dialNext: "Dial next"
        case .dialPress: "Dial press / hold"
        }
    }

    var systemImage: String {
        switch self {
        case .agent0, .agent1, .agent2, .agent3, .agent4, .agent5:
            "circle.fill"
        case .fastMode:
            "bolt.fill"
        case .approve:
            "checkmark.circle"
        case .reject:
            "xmark.circle"
        case .fork:
            "arrow.triangle.branch"
        case .pushToTalk, .pushToTalkSecondary:
            "mic"
        case .submit:
            "seal"
        case .stickUp:
            "arrow.up"
        case .stickRight:
            "arrow.right"
        case .stickDown:
            "arrow.down"
        case .stickLeft:
            "arrow.left"
        case .dialPrevious:
            "arrow.up"
        case .dialNext:
            "arrow.down"
        case .dialPress:
            "dot.circle"
        }
    }
}
