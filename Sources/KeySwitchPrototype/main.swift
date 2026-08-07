import ApplicationServices
import Foundation

private struct CodexDebugTarget: Decodable {
    let url: String
    let webSocketDebuggerUrl: String
}

private struct MicroKeyEvent: Encodable {
    let key: String
    let act: Int
    let agent: Int?
    let slot: Int?
    let threadKey: String?
}

/// Sends the same renderer events that the Codex desktop host normally emits
/// after receiving input from a physical Codex Micro.
private final class CodexMicroBridge {
    private let debugPort: Int
    private let queue = DispatchQueue(label: "com.keyswitch.codex-bridge")
    private var socket: URLSessionWebSocketTask?
    private var nextRequestID = 1
    private var queuedEvents: [MicroKeyEvent] = []
    private var isReady = false

    init(debugPort: Int) {
        self.debugPort = debugPort
    }

    func connect() {
        queue.async { [weak self] in
            self?.discoverRenderer()
        }
    }

    func send(key: String, action: Int, slot: Int?) {
        let event = MicroKeyEvent(
            key: key,
            act: action,
            agent: nil,
            slot: slot,
            threadKey: nil
        )

        queue.async { [weak self] in
            guard let self else { return }
            guard self.isReady else {
                self.queuedEvents.append(event)
                return
            }
            self.send(event)
        }
    }

    private func discoverRenderer() {
        guard let url = URL(string: "http://127.0.0.1:\(debugPort)/json/list") else {
            print("Bridge error: invalid debug URL")
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            self.queue.async {
                if let error {
                    print("Bridge error: Codex debug endpoint is unavailable (\(error.localizedDescription))")
                    return
                }

                do {
                    let targets = try JSONDecoder().decode([CodexDebugTarget].self, from: data ?? Data())
                    guard let target = targets.first(where: { $0.url == "app://-/index.html" }),
                          let socketURL = URL(string: target.webSocketDebuggerUrl) else {
                        print("Bridge error: isolated Codex renderer was not found")
                        return
                    }
                    self.openSocket(socketURL)
                } catch {
                    print("Bridge error: could not decode Codex targets (\(error.localizedDescription))")
                }
            }
        }.resume()
    }

    private func openSocket(_ url: URL) {
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        isReady = true

        sendConnectedState()
        queuedEvents.forEach(send)
        queuedEvents.removeAll(keepingCapacity: true)

        print("Bridge connected to the isolated Codex Micro window on port \(debugPort).")
        print("Hold Fn and use the mapped agent/action keys. Press Fn+Esc to stop.")
    }

    private func sendConnectedState() {
        let expression = """
        (() => {
          const state = {
            status: 'connected',
            transport: 'usb',
            model: 'codex-micro',
            error: null,
            battery: null
          };
          window.dispatchEvent(new MessageEvent('message', {
            data: {
              type: 'codex-micro-device-state-changed',
              state,
              cause: 'keyswitch-prototype'
            },
            origin: location.origin,
            source: window
          }));
          return true;
        })()
        """
        sendRuntimeExpression(expression)
    }

    private func send(_ event: MicroKeyEvent) {
        do {
            let eventData = try JSONEncoder().encode(event)
            guard let eventJSON = String(data: eventData, encoding: .utf8) else { return }
            let expression = """
            (() => {
              const event = \(eventJSON);
              window.dispatchEvent(new MessageEvent('message', {
                data: { type: 'codex-micro-hid-event', event },
                origin: location.origin,
                source: window
              }));
              return true;
            })()
            """
            sendRuntimeExpression(expression)
        } catch {
            print("Bridge error: could not encode key event (\(error.localizedDescription))")
        }
    }

    private func sendRuntimeExpression(_ expression: String) {
        guard let socket else { return }

        let message: [String: Any] = [
            "id": nextRequestID,
            "method": "Runtime.evaluate",
            "params": [
                "expression": expression,
                "returnByValue": true,
                "userGesture": true,
            ],
        ]
        nextRequestID += 1

        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            guard let json = String(data: data, encoding: .utf8) else { return }
            socket.send(.string(json)) { [weak self] error in
                guard let error else { return }
                self?.queue.async {
                    self?.isReady = false
                    print("Bridge error: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Bridge error: could not encode CDP request (\(error.localizedDescription))")
        }
    }
}

private final class KeyboardLayer {
    private struct Mapping {
        let microKey: String
        let slot: Int?
        let label: String
    }

    private static let mappings: [CGKeyCode: Mapping] = [
        12: Mapping(microKey: "AG00", slot: 0, label: "Q"),
        13: Mapping(microKey: "AG01", slot: 1, label: "W"),
        14: Mapping(microKey: "AG02", slot: 2, label: "E"),
        15: Mapping(microKey: "AG03", slot: 3, label: "R"),
        17: Mapping(microKey: "AG04", slot: 4, label: "T"),
        16: Mapping(microKey: "AG05", slot: 5, label: "Y"),
        0: Mapping(microKey: "ACT06", slot: nil, label: "A (Fast mode)"),
        1: Mapping(microKey: "ACT07", slot: nil, label: "S (Approve)"),
        2: Mapping(microKey: "ACT08", slot: nil, label: "D (Reject)"),
        3: Mapping(microKey: "ACT09", slot: nil, label: "F (Fork)"),
        49: Mapping(microKey: "ACT10", slot: nil, label: "Space (Push to talk)"),
    ]

    private static let rightCommandKeyCode: CGKeyCode = 54

    private let bridge: CodexMicroBridge
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnIsHeld = false
    private var rightCommandIsMicroKey = false
    private var activeKeyCodes = Set<CGKeyCode>()

    init(bridge: CodexMicroBridge) {
        self.bridge = bridge
    }

    func start() -> Bool {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: keyboardEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            print("Could not create the keyboard event tap.")
            print("Enable KeySwitch or its host app in System Settings → Privacy & Security → Accessibility and Input Monitoring, then retry.")
            return false
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let eventCarriesFn = event.flags.contains(.maskSecondaryFn)

        if type == .flagsChanged {
            if keyCode == Self.rightCommandKeyCode {
                if rightCommandIsMicroKey {
                    rightCommandIsMicroKey = false
                    bridge.send(key: "ACT12", action: 0, slot: nil)
                    print("Fn+Right Command (Codex/Submit) → ACT12 release")
                    return nil
                }

                if fnIsHeld || eventCarriesFn {
                    rightCommandIsMicroKey = true
                    bridge.send(key: "ACT12", action: 1, slot: nil)
                    print("Fn+Right Command (Codex/Submit) → ACT12 press")
                    return nil
                }
            }

            fnIsHeld = eventCarriesFn
            return Unmanaged.passUnretained(event)
        }

        let layerIsActive = fnIsHeld || eventCarriesFn

        if type == .keyDown, layerIsActive, keyCode == 53 {
            releaseAllActiveKeys()
            print("Fn+Esc received. Stopping KeySwitch prototype.")
            CFRunLoopStop(CFRunLoopGetMain())
            return nil
        }

        guard let mapping = Self.mappings[keyCode] else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown, layerIsActive {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !isRepeat, activeKeyCodes.insert(keyCode).inserted {
                bridge.send(key: mapping.microKey, action: 1, slot: mapping.slot)
                print("Fn+\(mapping.label) → \(mapping.microKey) press")
            }
            return nil
        }

        if type == .keyUp, activeKeyCodes.remove(keyCode) != nil {
            bridge.send(key: mapping.microKey, action: 0, slot: mapping.slot)
            print("Fn+\(mapping.label) → \(mapping.microKey) release")
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func releaseAllActiveKeys() {
        for keyCode in activeKeyCodes {
            guard let mapping = Self.mappings[keyCode] else { continue }
            bridge.send(key: mapping.microKey, action: 0, slot: mapping.slot)
        }
        activeKeyCodes.removeAll()

        if rightCommandIsMicroKey {
            rightCommandIsMicroKey = false
            bridge.send(key: "ACT12", action: 0, slot: nil)
        }
    }
}

private let keyboardEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let layer = Unmanaged<KeyboardLayer>.fromOpaque(userInfo).takeUnretainedValue()
    return layer.handle(type: type, event: event)
}

private func requestPermissionsIfNeeded() {
    if !CGPreflightListenEventAccess() {
        _ = CGRequestListenEventAccess()
    }

    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [promptKey: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
}

let debugPort = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 9348

print("KeySwitch Codex Micro keyboard-layer prototype")
print("Target debug port: \(debugPort)")
requestPermissionsIfNeeded()

private let bridge = CodexMicroBridge(debugPort: debugPort)
private let keyboardLayer = KeyboardLayer(bridge: bridge)

guard keyboardLayer.start() else {
    exit(EXIT_FAILURE)
}

bridge.connect()
CFRunLoopRun()
