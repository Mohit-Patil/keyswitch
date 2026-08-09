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
    private var suppressedModifierKeys: Set<UInt16> = []

    init(configuration: KeyboardEngineConfiguration) {
        self.configuration = configuration
        rebuildBindingIndexes()
    }

    func update(configuration: KeyboardEngineConfiguration) {
        releaseAllControls()
        setLayerActive(false)
        activationShortcutIsDown = false
        suppressedModifierKeys.removeAll()
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
        suppressedModifierKeys.removeAll()
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

    func deactivateLayer() {
        releaseAllControls()
        setLayerActive(false)
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            releaseAllControls()
            setLayerActive(false)
            activationShortcutIsDown = false
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                onTapStatusChanged?(true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .flagsChanged {
            let shortcutIsDown = configuration.activationShortcut.isPressed(in: event.flags)
            handleActivationShortcutChange(isDown: shortcutIsDown)

            // Fn-only activation owns both transitions so macOS does not also
            // open the Globe/emoji action. Multi-modifier shortcuts continue
            // to pass their modifier events through normally.
            if configuration.activationShortcut.isFunctionOnly,
               configuration.activationShortcut.contains(keyCode: keyCode) {
                return nil
            }

            // Chord activation modifiers pass through to macOS. In particular,
            // this lets Fn keep its Globe/emoji behavior when it is only one
            // part of a multi-modifier activation shortcut.
            if configuration.activationShortcut.contains(keyCode: keyCode) {
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

            let isDown = modifierIsDown(keyCode: keyCode, flags: event.flags)

            if suppressedModifierKeys.contains(keyCode) {
                if !isDown {
                    suppressedModifierKeys.remove(keyCode)
                    if let activeControl = activeModifierKeys.removeValue(forKey: keyCode) {
                        emit(activeControl, action: 0)
                    }
                }
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

        if type == .keyUp, let activeControl = activeRegularKeys.removeValue(forKey: keyCode) {
            emit(activeControl, action: 0)
            return nil
        }

        if type == .keyUp, activeStepKeys.remove(keyCode) != nil {
            return nil
        }

        guard layerIsActive else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown, keyCode == 53 {
            deactivateLayer()
            return nil
        }

        if let control = regularBindings[keyCode] {
            if type == .keyDown {
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                if !isRepeat {
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
            }
            return nil
        }

        if configuration.blockUnmappedKeys, (type == .keyDown || type == .keyUp) {
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
