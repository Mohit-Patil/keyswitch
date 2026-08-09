import Foundation

struct KeyBinding: Codable, Hashable, Identifiable {
    let control: MicroControl
    var physicalKey: PhysicalKey?

    var id: MicroControl { control }

    static let defaults: [KeyBinding] = [
        KeyBinding(control: .agent0, physicalKey: .one),
        KeyBinding(control: .agent1, physicalKey: .two),
        KeyBinding(control: .agent2, physicalKey: .three),
        KeyBinding(control: .agent3, physicalKey: .four),
        KeyBinding(control: .agent4, physicalKey: .five),
        KeyBinding(control: .agent5, physicalKey: .six),
        KeyBinding(control: .fastMode, physicalKey: .q),
        KeyBinding(control: .approve, physicalKey: .w),
        KeyBinding(control: .reject, physicalKey: .e),
        KeyBinding(control: .fork, physicalKey: .r),
        KeyBinding(control: .pushToTalk, physicalKey: .space),
        KeyBinding(control: .pushToTalkSecondary, physicalKey: nil),
        KeyBinding(control: .submit, physicalKey: .rightCommand),
        KeyBinding(control: .stickUp, physicalKey: .i),
        KeyBinding(control: .stickRight, physicalKey: .l),
        KeyBinding(control: .stickDown, physicalKey: .k),
        KeyBinding(control: .stickLeft, physicalKey: .j),
        KeyBinding(control: .dialPrevious, physicalKey: .tab),
        KeyBinding(control: .dialNext, physicalKey: .backtick),
        KeyBinding(control: .dialPress, physicalKey: .leftShift),
    ]

    static func mergingDefaults(into savedBindings: [KeyBinding]) -> [KeyBinding] {
        let layoutMigratedBindings = migratingLegacyAgentAndCommandDefaults(in: savedBindings)
        let stickMigratedBindings = migratingLegacyStickDefaults(in: layoutMigratedBindings)
        let legacyDialMigratedBindings = migratingLegacyDialDefaults(in: stickMigratedBindings)
        let migratedBindings = migratingCapsLockDialDefault(in: legacyDialMigratedBindings)
        var usedKeyIDs = Set(migratedBindings.compactMap { $0.physicalKey?.id })

        return defaults.map { defaultBinding in
            if let savedBinding = migratedBindings.first(where: { $0.control == defaultBinding.control }) {
                return savedBinding
            }

            guard let defaultKey = defaultBinding.physicalKey,
                  !usedKeyIDs.contains(defaultKey.id) else {
                return KeyBinding(control: defaultBinding.control, physicalKey: nil)
            }

            usedKeyIDs.insert(defaultKey.id)
            return defaultBinding
        }
    }

    /// Move only the complete former shipping layout. If the user changed any
    /// agent or command key, preserve their entire custom cluster as-is.
    private static func migratingLegacyAgentAndCommandDefaults(
        in savedBindings: [KeyBinding]
    ) -> [KeyBinding] {
        let stillUsesCompleteLegacyCluster = legacyAgentAndCommandDefaults.allSatisfy { entry in
            savedBindings.first(where: { $0.control == entry.key })?.physicalKey == entry.value
        }
        guard stillUsesCompleteLegacyCluster else { return savedBindings }

        let migratedControls = Set(newAgentAndCommandDefaults.keys)
        let keysUsedOutsideCluster = Set(
            savedBindings
                .filter { !migratedControls.contains($0.control) }
                .compactMap { $0.physicalKey?.id }
        )
        guard newAgentAndCommandDefaults.values.allSatisfy({
            !keysUsedOutsideCluster.contains($0.id)
        }) else {
            return savedBindings
        }

        return savedBindings.map { binding in
            guard let replacement = newAgentAndCommandDefaults[binding.control] else {
                return binding
            }
            return KeyBinding(control: binding.control, physicalKey: replacement)
        }
    }

    private static func migratingLegacyStickDefaults(
        in savedBindings: [KeyBinding]
    ) -> [KeyBinding] {
        let stillUsesCompleteLegacyCluster = legacyStickDefaults.allSatisfy { entry in
            savedBindings.first(where: { $0.control == entry.key })?.physicalKey == entry.value
        }
        guard stillUsesCompleteLegacyCluster else { return savedBindings }

        let stickControls = Set(newStickDefaults.keys)
        let keysUsedOutsideStick = Set(
            savedBindings
                .filter { !stickControls.contains($0.control) }
                .compactMap { $0.physicalKey?.id }
        )
        guard newStickDefaults.values.allSatisfy({ !keysUsedOutsideStick.contains($0.id) }) else {
            return savedBindings
        }

        return savedBindings.map { binding in
            guard let replacement = newStickDefaults[binding.control] else { return binding }
            return KeyBinding(control: binding.control, physicalKey: replacement)
        }
    }

    private static func migratingLegacyDialDefaults(
        in savedBindings: [KeyBinding]
    ) -> [KeyBinding] {
        let previous = savedBindings.first(where: { $0.control == .dialPrevious })?.physicalKey
        let next = savedBindings.first(where: { $0.control == .dialNext })?.physicalKey
        let press = savedBindings.first(where: { $0.control == .dialPress })?.physicalKey
        guard previous == nil, next == .g, press == .h else { return savedBindings }

        let dialControls: Set<MicroControl> = [.dialPrevious, .dialNext, .dialPress]
        let targetKeys = Set([
            PhysicalKey.tab.id,
            PhysicalKey.backtick.id,
            PhysicalKey.leftShift.id,
        ])
        let keysUsedOutsideDial = Set(
            savedBindings
                .filter { !dialControls.contains($0.control) }
                .compactMap { $0.physicalKey?.id }
        )
        guard targetKeys.isDisjoint(with: keysUsedOutsideDial) else { return savedBindings }

        var migrated = savedBindings.map { binding in
            switch binding.control {
            case .dialPrevious:
                KeyBinding(control: .dialPrevious, physicalKey: .tab)
            case .dialNext:
                KeyBinding(control: .dialNext, physicalKey: .backtick)
            case .dialPress:
                KeyBinding(control: .dialPress, physicalKey: .leftShift)
            default:
                binding
            }
        }
        if !migrated.contains(where: { $0.control == .dialPrevious }) {
            migrated.append(KeyBinding(control: .dialPrevious, physicalKey: .tab))
        }
        return migrated
    }

    /// Caps Lock is a latching system key: macOS changes its global state
    /// below a session event tap, even when KeySwitch consumes the event.
    /// Move only the complete former shipping cluster so customized mappings
    /// stay exactly as the user set them.
    private static func migratingCapsLockDialDefault(
        in savedBindings: [KeyBinding]
    ) -> [KeyBinding] {
        let previous = savedBindings.first(where: { $0.control == .dialPrevious })?.physicalKey
        let next = savedBindings.first(where: { $0.control == .dialNext })?.physicalKey
        let press = savedBindings.first(where: { $0.control == .dialPress })?.physicalKey
        guard previous == .tab, next == .capsLock, press == .leftShift else {
            return savedBindings
        }

        let dialControls: Set<MicroControl> = [.dialPrevious, .dialNext, .dialPress]
        let backtickIsUsedElsewhere = savedBindings.contains { binding in
            !dialControls.contains(binding.control) && binding.physicalKey == .backtick
        }
        guard !backtickIsUsedElsewhere else { return savedBindings }

        return savedBindings.map { binding in
            guard binding.control == .dialNext else { return binding }
            return KeyBinding(control: .dialNext, physicalKey: .backtick)
        }
    }

    private static let legacyStickDefaults: [MicroControl: PhysicalKey] = [
        .stickUp: .upArrow,
        .stickRight: .rightArrow,
        .stickDown: .downArrow,
        .stickLeft: .leftArrow,
    ]

    private static let newStickDefaults: [MicroControl: PhysicalKey] = [
        .stickUp: .i,
        .stickRight: .l,
        .stickDown: .k,
        .stickLeft: .j,
    ]

    private static let legacyAgentAndCommandDefaults: [MicroControl: PhysicalKey] = [
        .agent0: .q,
        .agent1: .w,
        .agent2: .e,
        .agent3: .r,
        .agent4: .t,
        .agent5: .y,
        .fastMode: .a,
        .approve: .s,
        .reject: .d,
        .fork: .f,
    ]

    private static let newAgentAndCommandDefaults: [MicroControl: PhysicalKey] = [
        .agent0: .one,
        .agent1: .two,
        .agent2: .three,
        .agent3: .four,
        .agent4: .five,
        .agent5: .six,
        .fastMode: .q,
        .approve: .w,
        .reject: .e,
        .fork: .r,
    ]
}
