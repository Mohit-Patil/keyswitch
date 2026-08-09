import Foundation

enum AgentLightStatus: String, Codable, CaseIterable, Equatable {
    case off
    case idle
    case working
    case unread
    case awaitingApproval = "awaiting-approval"
    case awaitingResponse = "awaiting-response"
    case error

    var title: String {
        switch self {
        case .off: "Unassigned"
        case .idle: "Idle"
        case .working: "Working"
        case .unread: "Complete"
        case .awaitingApproval: "Needs approval"
        case .awaitingResponse: "Needs response"
        case .error: "Error"
        }
    }

    /// The packed RGB values used by Codex for Micro agent-key lighting.
    var packedRGB: UInt32 {
        switch self {
        case .off: 0x000000
        case .idle: 0xFFFFFF
        case .working: 0x304FFE
        case .unread: 0x00FF4C
        case .awaitingApproval, .awaitingResponse: 0xFF6D00
        case .error: 0xFF0033
        }
    }
}

struct AgentLightState: Codable, Equatable, Identifiable {
    let id: Int
    let title: String?
    let threadKey: String?
    let status: AgentLightStatus
    let selected: Bool

    static let offSlots = (0..<6).map {
        AgentLightState(
            id: $0,
            title: nil,
            threadKey: nil,
            status: .off,
            selected: false
        )
    }
}

struct CodexLightingSnapshot: Codable, Equatable {
    let brightness: Double
    let inactivityTimeoutMs: Int
    let slots: [AgentLightState]

    var inactivityInterval: TimeInterval? {
        guard inactivityTimeoutMs > 0 else { return nil }
        return TimeInterval(inactivityTimeoutMs) / 1_000
    }

    static let off = CodexLightingSnapshot(
        brightness: 1,
        inactivityTimeoutMs: 180_000,
        slots: AgentLightState.offSlots
    )

    #if DEBUG
    static let preview = CodexLightingSnapshot(
        brightness: 1,
        inactivityTimeoutMs: 180_000,
        slots: [
            AgentLightState(id: 0, title: "Idle task", threadKey: "preview:0", status: .idle, selected: false),
            AgentLightState(id: 1, title: "Working task", threadKey: "preview:1", status: .working, selected: true),
            AgentLightState(id: 2, title: "Completed task", threadKey: "preview:2", status: .unread, selected: false),
            AgentLightState(id: 3, title: "Approval task", threadKey: "preview:3", status: .awaitingApproval, selected: false),
            AgentLightState(id: 4, title: "Failed task", threadKey: "preview:4", status: .error, selected: false),
            AgentLightState(id: 5, title: nil, threadKey: nil, status: .off, selected: false),
        ]
    )
    #endif

    func light(for slot: Int) -> AgentLightState {
        if let light = slots.first(where: { $0.id == slot }) {
            return light
        }
        return AgentLightState(
            id: slot,
            title: nil,
            threadKey: nil,
            status: .off,
            selected: false
        )
    }

}
