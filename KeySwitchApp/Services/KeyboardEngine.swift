import ApplicationServices
import Foundation

struct KeyboardEngineConfiguration {
    var activationMode: ActivationMode
    var activationShortcut: ActivationShortcut
    var blockUnmappedKeys: Bool
    var bindings: [KeyBinding]
}

final class KeyboardEngine {
    var onLayerStateChanged: ((Bool) -> Void)?
    var onControlEvent: ((MicroControl, Int) -> Void)?
    var onTapStatusChanged: ((Bool) -> Void)?

    private var configuration: KeyboardEngineConfiguration
    private var regularBindings: [UInt16: MicroControl] = [:]
    private var modifierBindings: [UInt16: MicroControl] = [:]
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activationShortcutIsDown = false
    private var layerIsActive = false
    private var activeRegularKeys: [UInt16: MicroControl] = [:]
    private var activeStepKeys: Set<UInt16> = []
    private var activeModifierKeys: [UInt16: MicroControl] = [:]
    private var suppressedRegularKeys: Set<UInt16> = []
    private var suppressedModifierKeys: Set<UInt16> = []
    private var suppressedActivationKeys: Set<UInt16> = []
    private var suppressedActivationModifiers: Set<UInt16> = []
    private var shortcutCaptureIsActive = false
    private var shortcutCaptureHandler: ((PhysicalKey, Set<ActivationModifier>) -> Void)?
    private var shortcutCaptureCancellationHandler: (() -> Void)?
    private var shortcutCapturePendingKey: PhysicalKey?
    private var shortcutCapturePendingModifiers: Set<ActivationModifier> = []
    private var shortcutCaptureRegularKeys: Set<UInt16> = []
    private var shortcutCaptureModifierKeys: Set<UInt16> = []
    private let captureEventTapIsReady: (CFMachPort?) -> Bool

    init(
        configuration: KeyboardEngineConfiguration,
        captureEventTapIsReady: @escaping (CFMachPort?) -> Bool = { eventTap in
            guard let eventTap, CFMachPortIsValid(eventTap) else { return false }
            return CGEvent.tapIsEnabled(tap: eventTap)
        }
    ) {
        self.configuration = configuration
        self.captureEventTapIsReady = captureEventTapIsReady
        rebuildBindingIndexes()
    }

    func update(configuration: KeyboardEngineConfiguration) {
        releaseAllControls()
        setLayerActive(false)
        activationShortcutIsDown = false
        self.configuration = configuration
        rebuildBindingIndexes()
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: keySwitchEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            onTapStatusChanged?(false)
            return false
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        onTapStatusChanged?(true)
        return true
    }

    func stop() {
        releaseAllControls()
        setLayerActive(false)
        activationShortcutIsDown = false
        suppressedRegularKeys.removeAll()
        suppressedActivationKeys.removeAll()
        suppressedActivationModifiers.removeAll()
        suppressedModifierKeys.removeAll()
        shortcutCaptureRegularKeys.removeAll()
        shortcutCaptureModifierKeys.removeAll()
        cancelShortcutCapture()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
        onTapStatusChanged?(false)
    }

    func toggleLayerFromMenu() {
        setLayerActive(!layerIsActive)
    }

    @discardableResult
    func beginShortcutCapture(
        onCapture: @escaping (PhysicalKey, Set<ActivationModifier>) -> Void,
        onCancel: @escaping () -> Void
    ) -> Bool {
        guard captureEventTapIsReady(eventTap) else { return false }

        releaseAllControls()
        setLayerActive(false)
        activationShortcutIsDown = false
        shortcutCapturePendingKey = nil
        shortcutCapturePendingModifiers = []
        shortcutCaptureHandler = onCapture
        shortcutCaptureCancellationHandler = onCancel
        shortcutCaptureIsActive = true
        return true
    }

    func cancelShortcutCapture() {
        shortcutCaptureIsActive = false
        shortcutCaptureHandler = nil
        shortcutCaptureCancellationHandler = nil
        shortcutCapturePendingKey = nil
        shortcutCapturePendingModifiers = []
    }

    func deactivateLayer() {
        releaseAllControls()
        setLayerActive(false)
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let captureCancellationHandler = shortcutCaptureCancellationHandler
            cancelShortcutCapture()
            releaseAllControls()
            setLayerActive(false)
            activationShortcutIsDown = false
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                onTapStatusChanged?(true)
            }
            captureCancellationHandler?()
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Finish every transition whose matching press KeySwitch consumed,
        // even after the layer, configuration, or recorder state changes.
        if type == .keyDown,
           suppressedActivationKeys.contains(keyCode) || suppressedRegularKeys.contains(keyCode) {
            return nil
        }
        if type == .keyUp, suppressedActivationKeys.remove(keyCode) != nil {
            if activationShortcutIsDown {
                handleActivationShortcutChange(isDown: false)
            }
            return nil
        }
        if type == .keyUp, suppressedRegularKeys.remove(keyCode) != nil {
            if let activeControl = activeRegularKeys.removeValue(forKey: keyCode) {
                emit(activeControl, action: 0)
            }
            activeStepKeys.remove(keyCode)
            return nil
        }
        if !shortcutCaptureIsActive,
           type == .keyDown,
           shortcutCaptureRegularKeys.contains(keyCode) {
            return nil
        }
        if !shortcutCaptureIsActive,
           type == .keyUp,
           shortcutCaptureRegularKeys.remove(keyCode) != nil {
            return nil
        }

        if type == .flagsChanged, suppressedActivationModifiers.contains(keyCode) {
            suppressedActivationModifiers.remove(keyCode)
            if activationShortcutIsDown {
                handleActivationShortcutChange(isDown: false)
            }
            return nil
        }
        if type == .flagsChanged, suppressedModifierKeys.contains(keyCode) {
            suppressedModifierKeys.remove(keyCode)
            if let activeControl = activeModifierKeys.removeValue(forKey: keyCode) {
                emit(activeControl, action: 0)
            }
            return nil
        }
        if !shortcutCaptureIsActive,
           type == .flagsChanged,
           shortcutCaptureModifierKeys.contains(keyCode) {
            shortcutCaptureModifierKeys.remove(keyCode)
            return nil
        }

        if shortcutCaptureIsActive {
            return handleShortcutCapture(type: type, event: event, keyCode: keyCode)
        }

        if type == .flagsChanged {
            let isDown = modifierIsDown(keyCode: keyCode, flags: event.flags)
            let activationShortcut = configuration.activationShortcut
            if activationShortcut.isModifierOnly {
                handleActivationShortcutChange(
                    isDown: activationShortcut.isPressed(in: event.flags)
                )
            } else if activationShortcutIsDown,
                      !activationShortcut.modifiersArePressed(in: event.flags) {
                // A keyed Hold shortcut ends as soon as one of its required
                // modifiers is released. Its trigger key-up remains captured
                // separately so macOS never receives half of a key press.
                handleActivationShortcutChange(isDown: false)
            }

            // Own Fn when it is the complete shortcut or part of a keyed
            // shortcut. Otherwise macOS can interpret the swallowed trigger
            // key as an Fn-alone press and open Globe/emoji unexpectedly.
            let ownsFunctionPress = keyCode == 63
                && isDown
                && (activationShortcut.isFunctionOnly
                    || (activationShortcut.key != nil
                        && activationShortcut.modifiers.contains(.function)))
            if ownsFunctionPress {
                suppressedActivationModifiers.insert(keyCode)
                return nil
            }

            // Other chord activation modifiers pass through to macOS.
            if configuration.activationShortcut.containsModifier(keyCode: keyCode) {
                return Unmanaged.passUnretained(event)
            }

            // Caps Lock reports its toggled state instead of a conventional
            // key-down/key-up pair. While it is mapped in the active layer,
            // treat every state transition as one virtual button tap. The
            // shipping defaults avoid this latching system key, but existing
            // custom mappings remain supported.
            if keyCode == 57, layerIsActive, let control = modifierBindings[keyCode] {
                emit(control, action: 1)
                emit(control, action: 0)
                return nil
            }

            if layerIsActive, isDown {
                if let control = modifierBindings[keyCode] {
                    suppressedModifierKeys.insert(keyCode)
                    if control.interactionKind == .step {
                        emit(control, action: 1)
                        emit(control, action: 0)
                    } else {
                        activeModifierKeys[keyCode] = control
                        emit(control, action: 1)
                    }
                    return nil
                }

                if configuration.blockUnmappedKeys {
                    suppressedModifierKeys.insert(keyCode)
                    return nil
                }
            }

            return Unmanaged.passUnretained(event)
        }

        if let activationKey = configuration.activationShortcut.key,
           activationKey.keyCode == keyCode,
           type == .keyDown {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !isRepeat,
               configuration.activationShortcut.modifiersMatchExactly(in: event.flags) {
                suppressedActivationKeys.insert(keyCode)
                handleActivationShortcutChange(isDown: true)
                return nil
            }
        }

        guard layerIsActive else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown, keyCode == 53 {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !isRepeat {
                suppressedRegularKeys.insert(keyCode)
            }
            deactivateLayer()
            return nil
        }

        if let control = regularBindings[keyCode] {
            if type == .keyDown {
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                if !isRepeat {
                    suppressedRegularKeys.insert(keyCode)
                    if control.interactionKind == .step, !activeStepKeys.contains(keyCode) {
                        activeStepKeys.insert(keyCode)
                        emit(control, action: 1)
                        emit(control, action: 0)
                    } else if control.interactionKind == .momentary,
                              activeRegularKeys[keyCode] == nil {
                        activeRegularKeys[keyCode] = control
                        emit(control, action: 1)
                    }
                }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        if configuration.blockUnmappedKeys {
            if type == .keyDown {
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                if !isRepeat {
                    suppressedRegularKeys.insert(keyCode)
                }
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleShortcutCapture(
        type: CGEventType,
        event: CGEvent,
        keyCode: UInt16
    ) -> Unmanaged<CGEvent>? {
        if type == .flagsChanged {
            if shortcutCaptureModifierKeys.contains(keyCode) {
                shortcutCaptureModifierKeys.remove(keyCode)
            } else {
                shortcutCaptureModifierKeys.insert(keyCode)
            }
            return nil
        }

        if type == .keyDown {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            guard !isRepeat else { return nil }

            shortcutCaptureRegularKeys.insert(keyCode)
            if shortcutCapturePendingKey == nil,
               let key = PhysicalKey.from(event: event),
               !key.isModifier {
                shortcutCapturePendingKey = key
                shortcutCapturePendingModifiers = Set(
                    ActivationModifier.allCases.filter { $0.isPressed(in: event.flags) }
                )
            }
            return nil
        }

        if type == .keyUp, shortcutCaptureRegularKeys.remove(keyCode) != nil {
            guard let pendingKey = shortcutCapturePendingKey,
                  pendingKey.keyCode == keyCode else { return nil }

            let modifiers = shortcutCapturePendingModifiers
            let handler = shortcutCaptureHandler
            shortcutCaptureIsActive = false
            shortcutCaptureHandler = nil
            shortcutCaptureCancellationHandler = nil
            shortcutCapturePendingKey = nil
            shortcutCapturePendingModifiers = []
            handler?(pendingKey, modifiers)
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleActivationShortcutChange(isDown: Bool) {
        guard isDown != activationShortcutIsDown else { return }
        activationShortcutIsDown = isDown

        switch configuration.activationMode {
        case .hold:
            if !isDown {
                releaseAllControls()
            }
            setLayerActive(isDown)
        case .toggle:
            if isDown {
                if layerIsActive {
                    releaseAllControls()
                }
                setLayerActive(!layerIsActive)
            }
        }
    }

    private func rebuildBindingIndexes() {
        regularBindings.removeAll(keepingCapacity: true)
        modifierBindings.removeAll(keepingCapacity: true)

        for binding in configuration.bindings {
            guard let key = binding.physicalKey else { continue }
            if key.isModifier {
                modifierBindings[key.keyCode] = binding.control
            } else {
                regularBindings[key.keyCode] = binding.control
            }
        }
    }

    private func releaseAllControls() {
        activeRegularKeys.values.forEach { emit($0, action: 0) }
        activeModifierKeys.values.forEach { emit($0, action: 0) }
        activeRegularKeys.removeAll()
        activeStepKeys.removeAll()
        activeModifierKeys.removeAll()
    }

    private func emit(_ control: MicroControl, action: Int) {
        onControlEvent?(control, action)
    }

    private func modifierIsDown(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 54, 55:
            flags.contains(.maskCommand)
        case 56, 60:
            flags.contains(.maskShift)
        case 57:
            flags.contains(.maskAlphaShift)
        case 58, 61:
            flags.contains(.maskAlternate)
        case 59, 62:
            flags.contains(.maskControl)
        case 63:
            flags.contains(.maskSecondaryFn)
        default:
            false
        }
    }

    private func setLayerActive(_ active: Bool) {
        guard layerIsActive != active else { return }
        layerIsActive = active
        onLayerStateChanged?(active)
    }
}

private let keySwitchEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let engine = Unmanaged<KeyboardEngine>.fromOpaque(userInfo).takeUnretainedValue()
    return engine.handle(type: type, event: event)
}
