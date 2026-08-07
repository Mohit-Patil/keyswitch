import Foundation

enum AutoDimTimeout: Int, Codable, CaseIterable, Identifiable {
    case oneMinute = 60
    case threeMinutes = 180
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case never = 0

    var id: Self { self }

    var title: String {
        switch self {
        case .oneMinute: "1 minute"
        case .threeMinutes: "3 minutes"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .never: "Never"
        }
    }

    var interval: TimeInterval? {
        rawValue == 0 ? nil : TimeInterval(rawValue)
    }
}

enum MicroKeycap: String, Codable, CaseIterable, Hashable, Identifiable {
    case fast
    case approve
    case reject
    case fork
    case microphone
    case microphoneDouble
    case codex
    case bug
    case openAI
    case terminal
    case download
    case delete
    case newChat
    case navigation
    case magic
    case diff
    case play
    case git
    case draft
    case branch
    case merge
    case pullRequest
    case paint
    case lab
    case party
    case time
    case mindPlus
    case mindMinus
    case empty1
    case empty2
    case empty3
    case empty4
    case empty5
    case setup
    case folder
    case upload
    case apps
    case yolo
    case yeet

    var id: Self { self }

    init?(codexID: String) {
        switch codexID {
        case "FAST": self = .fast
        case "APPR": self = .approve
        case "REJ": self = .reject
        case "SPLIT": self = .fork
        case "MIC": self = .microphoneDouble
        case "MIC1": self = .microphone
        case "CODEX": self = .codex
        case "BUG": self = .bug
        case "OAI": self = .openAI
        case "TERM": self = .terminal
        case "DWN": self = .download
        case "DEL": self = .delete
        case "NEW": self = .newChat
        case "NAV": self = .navigation
        case "MAGIC": self = .magic
        case "DIFF": self = .diff
        case "PLAY": self = .play
        case "GIT": self = .git
        case "BRCH": self = .draft
        case "BRANCH": self = .branch
        case "MRG": self = .merge
        case "PR": self = .pullRequest
        case "PAINT": self = .paint
        case "LAB": self = .lab
        case "PARTY": self = .party
        case "TIME": self = .time
        case "MIND+": self = .mindPlus
        case "MIND-": self = .mindMinus
        case "EMPT1": self = .empty1
        case "EMPT2": self = .empty2
        case "EMPT3": self = .empty3
        case "EMPT4": self = .empty4
        case "EMPT5": self = .empty5
        case "SETUP": self = .setup
        case "FOLD": self = .folder
        case "UPL": self = .upload
        case "APPS": self = .apps
        case "YOLO": self = .yolo
        case "YEET": self = .yeet
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .fast: "FAST"
        case .approve: "APPR"
        case .reject: "REJ"
        case .fork: "FORK"
        case .microphone: "MIC1"
        case .microphoneDouble: "MIC"
        case .codex: "CODEX"
        case .bug: "BUG"
        case .openAI: "OAI"
        case .terminal: "TERM"
        case .download: "DWN"
        case .delete: "DEL"
        case .newChat: "NEW"
        case .navigation: "NAV"
        case .magic: "MAGIC"
        case .diff: "DIFF"
        case .play: "PLAY"
        case .git: "GIT"
        case .draft: "DRAFT"
        case .branch: "BRANCH"
        case .merge: "MRG"
        case .pullRequest: "PR"
        case .paint: "PAINT"
        case .lab: "LAB"
        case .party: "PARTY"
        case .time: "TIME"
        case .mindPlus: "MIND+"
        case .mindMinus: "MIND-"
        case .empty1: "EMPT1"
        case .empty2: "EMPT2"
        case .empty3: "EMPT3"
        case .empty4: "EMPT4"
        case .empty5: "EMPT5"
        case .setup: "SETUP"
        case .folder: "FOLD"
        case .upload: "UPL"
        case .apps: "APPS"
        case .yolo: "YOLO"
        case .yeet: "YEET"
        }
    }

    var title: String {
        switch self {
        case .fast: "Toggle Fast mode"
        case .approve: "Approve"
        case .reject: "Reject"
        case .fork: "Continue in new chat"
        case .microphone, .microphoneDouble: "Push to talk"
        case .codex: "Send message"
        case .bug: "Bug"
        case .openAI: "OpenAI"
        case .terminal: "Terminal"
        case .download: "Copy conversation as Markdown"
        case .delete: "Archive task"
        case .newChat: "New task"
        case .navigation: "Open browser"
        case .magic: "Pin or unpin task"
        case .diff: "Toggle review"
        case .play: "Environment action"
        case .git: "Commit"
        case .draft: "Create draft pull request"
        case .branch: "Create branch"
        case .merge: "Merge pull request"
        case .pullRequest: "Create pull request"
        case .paint: "Add photos"
        case .lab: "Settings"
        case .party: "Open side chat"
        case .time: "Manage tasks"
        case .mindPlus: "More thinking"
        case .mindMinus: "Less thinking"
        case .empty1, .empty2, .empty3, .empty4, .empty5: "Empty"
        case .setup: "Settings"
        case .folder: "Open folder"
        case .upload: "Add files"
        case .apps: "Open skills"
        case .yolo: "YOLO"
        case .yeet: "Yeet"
        }
    }

    var systemImage: String? {
        switch self {
        case .fast: "bolt"
        case .approve: "checkmark.circle"
        case .reject: "xmark.circle"
        case .fork: "arrow.triangle.branch"
        case .microphone, .microphoneDouble: "mic"
        case .codex: "seal"
        case .bug: "ant"
        case .openAI: "sparkles"
        case .terminal: "terminal"
        case .download: "arrow.down.to.line"
        case .delete: "trash"
        case .newChat: "square.and.pencil"
        case .navigation: "location"
        case .magic: "star"
        case .diff: "rectangle.split.2x1"
        case .play: "play"
        case .git: "plusminus"
        case .draft: "point.3.connected.trianglepath.dotted"
        case .branch: "point.topleft.down.to.point.bottomright.curvepath"
        case .merge: "arrow.triangle.merge"
        case .pullRequest: "arrow.triangle.pull"
        case .paint: "paintbrush"
        case .lab: "flask"
        case .party: "party.popper"
        case .time: "clock"
        case .mindPlus, .mindMinus: "brain"
        case .empty1, .empty2, .empty3, .empty4, .empty5: nil
        case .setup: "gearshape"
        case .folder: "folder.badge.plus"
        case .upload: "arrow.up.to.line"
        case .apps: "circle.grid.2x2"
        case .yolo, .yeet: nil
        }
    }

    var textGlyph: String? {
        switch self {
        case .yolo: ":yolo:"
        case .yeet: ":yeet:"
        default: nil
        }
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(needle)
            || title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(needle)
    }

    static func defaultValue(for control: MicroControl) -> MicroKeycap {
        switch control {
        case .fastMode: .fast
        case .approve: .approve
        case .reject: .reject
        case .fork: .fork
        case .pushToTalk, .pushToTalkSecondary: .microphone
        case .submit: .codex
        default: .empty1
        }
    }
}

struct CodexMicroSlotLayout: Codable, Equatable {
    let keycapId: String
}

struct CodexMicroLayoutSnapshot: Codable, Equatable {
    let version: Int
    let slots: [String: CodexMicroSlotLayout]
    let encoderMode: String
    let voiceButtonMode: String
    let separateMicrophoneKeys: Bool
    let agentSource: String
    let singleTapAgentKeys: Bool

    func keycap(for control: MicroControl) -> MicroKeycap? {
        guard control.supportsKeycapAppearance else { return nil }

        let slotID: String
        if control == .pushToTalk, !separateMicrophoneKeys {
            slotID = "ACT10_ACT11"
        } else {
            slotID = control.microKey
        }

        guard let keycapID = slots[slotID]?.keycapId else {
            return .defaultValue(for: control)
        }
        return MicroKeycap(codexID: keycapID) ?? .defaultValue(for: control)
    }

    var encoderModeTitle: String {
        switch encoderMode {
        case "reasoning": "Reasoning effort"
        case "conversation-scroll": "Conversation scroll"
        case "custom": "Custom"
        default: "Composer navigation"
        }
    }

    var voiceButtonModeTitle: String {
        switch voiceButtonMode {
        case "realtime": "Realtime voice"
        default: "Push to talk"
        }
    }

    var agentSourceTitle: String {
        switch agentSource {
        case "pinned": "Pinned tasks"
        case "priority": "Priority tasks"
        case "custom": "Custom"
        default: "Most recent tasks"
        }
    }

    static let codexDefault = CodexMicroLayoutSnapshot(
        version: 1,
        slots: [
            "ACT06": CodexMicroSlotLayout(keycapId: "FAST"),
            "ACT07": CodexMicroSlotLayout(keycapId: "APPR"),
            "ACT08": CodexMicroSlotLayout(keycapId: "REJ"),
            "ACT09": CodexMicroSlotLayout(keycapId: "SPLIT"),
            "ACT10": CodexMicroSlotLayout(keycapId: "MIC1"),
            "ACT11": CodexMicroSlotLayout(keycapId: "EMPT1"),
            "ACT10_ACT11": CodexMicroSlotLayout(keycapId: "MIC"),
            "ACT12": CodexMicroSlotLayout(keycapId: "CODEX"),
        ],
        encoderMode: "composer-navigation",
        voiceButtonMode: "push-to-talk",
        separateMicrophoneKeys: false,
        agentSource: "recent",
        singleTapAgentKeys: false
    )
}

extension MicroControl {
    static let customizableKeycapControls: [MicroControl] = [
        .fastMode,
        .approve,
        .reject,
        .fork,
        .pushToTalk,
        .pushToTalkSecondary,
        .submit,
    ]

    var supportsKeycapAppearance: Bool {
        Self.customizableKeycapControls.contains(self)
    }

    var isAgentKey: Bool { slot != nil }

    var isStickControl: Bool {
        switch self {
        case .stickUp, .stickRight, .stickDown, .stickLeft: true
        default: false
        }
    }

    var isDialControl: Bool {
        self == .dialPrevious || self == .dialNext || self == .dialPress
    }
}
