import Foundation

struct KeyBinding: Codable, Hashable, Identifiable {
    let control: MicroControl
    var physicalKey: PhysicalKey?

    var id: MicroControl { control }

    static let defaults: [KeyBinding] = [
        KeyBinding(control: .agent0, physicalKey: .q),
        KeyBinding(control: .agent1, physicalKey: .w),
        KeyBinding(control: .agent2, physicalKey: .e),
        KeyBinding(control: .agent3, physicalKey: .r),
        KeyBinding(control: .agent4, physicalKey: .t),
        KeyBinding(control: .agent5, physicalKey: .y),
        KeyBinding(control: .fastMode, physicalKey: .a),
        KeyBinding(control: .approve, physicalKey: .s),
        KeyBinding(control: .reject, physicalKey: .d),
        KeyBinding(control: .fork, physicalKey: .f),
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
        let stickMigratedBindings = migratingLegacyStickDefaults(in: savedBindings)
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
}
