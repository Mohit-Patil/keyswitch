import AppKit
import Foundation

enum BridgeStatus: String {
    case disconnected
    case connecting
    case connected

    var title: String {
        switch self {
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        }
    }

}

private struct CodexDebugTarget: Decodable {
    let url: String
    let webSocketDebuggerUrl: String
}

enum CodexBridgeEndpointPolicy {
    static let maximumDiscoveryResponseBytes = 1_048_576

    private static let validWebSocketSchemes = Set(["ws", "wss"])
    private static let numericLoopbackHosts = Set(["127.0.0.1", "[::1]"])

    static func discoveryURL(debugPort: Int) -> URL? {
        guard (1...65_535).contains(debugPort) else { return nil }
        return URL(string: "http://127.0.0.1:\(debugPort)/json/list")
    }

    static func isExpectedDiscoveryResponseURL(_ url: URL?, debugPort: Int) -> Bool {
        guard (1...65_535).contains(debugPort),
              let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "http",
              components.host?.lowercased() == "127.0.0.1",
              components.port == debugPort,
              components.user == nil,
              components.password == nil,
              components.percentEncodedPath == "/json/list",
              components.percentEncodedQuery == nil,
              components.fragment == nil else {
            return false
        }
        return true
    }

    static func validatedWebSocketURL(_ rawValue: String, debugPort: Int) -> URL? {
        guard (1...65_535).contains(debugPort),
              let components = URLComponents(string: rawValue),
              let scheme = components.scheme?.lowercased(),
              validWebSocketSchemes.contains(scheme),
              let host = components.host?.lowercased(),
              numericLoopbackHosts.contains(host),
              components.port == debugPort,
              components.user == nil,
              components.password == nil,
              components.percentEncodedQuery == nil,
              components.fragment == nil else {
            return nil
        }

        let pathSegments = components.percentEncodedPath.split(
            separator: "/",
            omittingEmptySubsequences: true
        )
        guard pathSegments.count == 3,
              pathSegments[0] == "devtools",
              pathSegments[1] == "page",
              !pathSegments[2].isEmpty,
              pathSegments[2].unicodeScalars.allSatisfy({ scalar in
                  CharacterSet.alphanumerics.contains(scalar)
                      || scalar == "-"
                      || scalar == "_"
              }) else {
            return nil
        }
        return components.url
    }

    static func canAccumulateDiscoveryResponse(
        currentByteCount: Int,
        incomingByteCount: Int
    ) -> Bool {
        guard currentByteCount >= 0,
              incomingByteCount >= 0,
              currentByteCount <= maximumDiscoveryResponseBytes else {
            return false
        }
        return incomingByteCount <= maximumDiscoveryResponseBytes - currentByteCount
    }
}

enum CodexBridgePollingPolicy {
    static let lightingIntervalMilliseconds = 900
    static let layoutPollEveryLightingTicks = 3

    static func shouldPollLayout(onLightingTick tick: Int) -> Bool {
        tick > 0 && tick.isMultiple(of: layoutPollEveryLightingTicks)
    }
}

private final class NoRedirectURLSessionDelegate: NSObject, URLSessionTaskDelegate {
    static let shared = NoRedirectURLSessionDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private enum BoundedDiscoveryRequestError: Error {
    case responseTooLarge
}

// URLSession may invoke cancellation and delegate callbacks on different
// threads. Every mutable field below is protected by stateLock.
private final class BoundedDiscoveryRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private typealias Completion = (Data?, URLResponse?, Error?) -> Void

    private let maximumResponseBytes: Int
    private let stateLock = NSLock()
    private var completion: Completion?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: URLResponse?
    private var receivedData = Data()
    private var isFinished = false

    init(maximumResponseBytes: Int) {
        self.maximumResponseBytes = maximumResponseBytes
    }

    func start(
        url: URL,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 5
        configuration.urlCache = nil
        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
        let task = session.dataTask(with: url)

        stateLock.lock()
        self.completion = completion
        self.session = session
        self.task = task
        stateLock.unlock()

        task.resume()
    }

    func cancel() {
        stateLock.lock()
        let task = task
        stateLock.unlock()
        task?.cancel()
        finish(error: URLError(.cancelled))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if response.expectedContentLength > Int64(maximumResponseBytes) {
            completionHandler(.cancel)
            finish(error: BoundedDiscoveryRequestError.responseTooLarge)
            return
        }

        stateLock.lock()
        let isFinished = isFinished
        if !isFinished {
            self.response = response
        }
        stateLock.unlock()
        completionHandler(isFinished ? .cancel : .allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        stateLock.lock()
        let canAccumulate = !isFinished && CodexBridgeEndpointPolicy.canAccumulateDiscoveryResponse(
            currentByteCount: receivedData.count,
            incomingByteCount: data.count
        )
        if canAccumulate {
            receivedData.append(data)
        }
        stateLock.unlock()

        guard canAccumulate else {
            dataTask.cancel()
            finish(error: BoundedDiscoveryRequestError.responseTooLarge)
            return
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        finish(error: error)
    }

    private func finish(error: Error?) {
        stateLock.lock()
        guard !isFinished else {
            stateLock.unlock()
            return
        }
        isFinished = true
        let completion = completion
        self.completion = nil
        let data = error == nil ? receivedData : nil
        let response = response
        let session = session
        self.session = nil
        task = nil
        receivedData.removeAll(keepingCapacity: false)
        stateLock.unlock()

        session?.invalidateAndCancel()
        completion?(data, response, error)
    }
}

struct CodexMicroKeyEvent: Encodable, Equatable {
    let key: String
    let act: Int
    let agent: Int?
    let slot: Int?
    let threadKey: String?
}

struct CodexMicroJoystickEvent: Encodable, Equatable {
    let angle: Double
    let distance: Double
}

enum CodexMicroOutboundEvent: Equatable {
    case key(CodexMicroKeyEvent)
    case joystick(CodexMicroJoystickEvent)
}

// All mutable bridge state is confined to queue. The unchecked conformance
// makes that explicit to Swift's strict-concurrency diagnostics while the
// public callbacks continue to publish on the main queue.
final class CodexMicroBridge: @unchecked Sendable {
    private typealias ProtocolCompletion = (Any?) -> Void

    private let queue = DispatchQueue(label: "com.keyswitch.codex-bridge")
    private let webSocketSession: URLSession
    private var discoveryRequest: BoundedDiscoveryRequest?
    private var socket: URLSessionWebSocketTask?
    private var nextRequestID = 1
    private var pendingResponses: [Int: ProtocolCompletion] = [:]
    private var lightingPollTimer: DispatchSourceTimer?
    private var lightingPollIsInFlight = false
    private var layoutPollIsInFlight = false
    private var lightingPollTick = 0
    private var lightingSnapshot = CodexLightingSnapshot.off
    private var layoutSnapshot: CodexMicroLayoutSnapshot?
    private var debugPort: Int
    private var isReady = false
    private var shouldReconnect = false
    private var connectionAttempt = 0
    private var reconnectWorkItem: DispatchWorkItem?

    var onStatusChange: ((BridgeStatus) -> Void)?
    var onLightingChange: ((CodexLightingSnapshot) -> Void)?
    var onLayoutChange: ((CodexMicroLayoutSnapshot) -> Void)?

    init(debugPort: Int) {
        self.debugPort = debugPort
        let webSocketConfiguration = URLSessionConfiguration.ephemeral
        webSocketConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        webSocketConfiguration.urlCache = nil
        webSocketSession = URLSession(
            configuration: webSocketConfiguration,
            delegate: NoRedirectURLSessionDelegate.shared,
            delegateQueue: nil
        )
    }

    deinit {
        discoveryRequest?.cancel()
        webSocketSession.invalidateAndCancel()
    }

    func connect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.shouldReconnect = true
            self.beginConnection()
        }
    }

    func reconnect(debugPort: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            self.debugPort = debugPort
            self.shouldReconnect = true
            self.beginConnection()
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.shouldReconnect = false
            self.connectionAttempt += 1
            self.cancelScheduledReconnect()
            self.disconnectInternal(updateStatus: true)
        }
    }

    func send(control: MicroControl, action: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let event = Self.outboundEvent(
                for: control,
                action: action,
                lightingSnapshot: self.lightingSnapshot
            ) else { return }

            switch event {
            case .key(let keyEvent):
                self.send(keyEvent)
            case .joystick(let joystickEvent):
                self.sendJoystick(joystickEvent)
            }
        }
    }

    static func outboundEvent(
        for control: MicroControl,
        action: Int,
        lightingSnapshot: CodexLightingSnapshot
    ) -> CodexMicroOutboundEvent? {
        switch control {
        case .dialPrevious, .dialNext:
            guard action == 1, let key = control.codexEncoderKey else { return nil }
            return .key(
                CodexMicroKeyEvent(
                    key: key,
                    act: 2,
                    agent: nil,
                    slot: nil,
                    threadKey: nil
                )
            )
        case .dialPress:
            guard let key = control.codexEncoderKey else { return nil }
            return .key(
                CodexMicroKeyEvent(
                    key: key,
                    act: action,
                    agent: nil,
                    slot: nil,
                    threadKey: nil
                )
            )
        case .stickUp, .stickRight, .stickDown, .stickLeft:
            guard let angle = control.codexJoystickAngle else { return nil }
            return .joystick(
                CodexMicroJoystickEvent(
                    angle: action == 1 ? angle : 0,
                    distance: action == 1 ? 1 : 0
                )
            )
        default:
            let slot = control.slot
            return .key(
                CodexMicroKeyEvent(
                    key: control.microKey,
                    act: action,
                    agent: nil,
                    slot: slot,
                    threadKey: slot.flatMap { lightingSnapshot.light(for: $0).threadKey }
                )
            )
        }
    }

    func openMicroSettings() {
        queue.async { [weak self] in
            self?.sendRuntimeExpression(
                """
                (async () => {
                  await window.electronBridge.sendMessageFromView({
                    type: 'persisted-atom-update',
                    key: 'codex-micro-has-ever-been-detected',
                    value: true,
                    deleted: false
                  });
                  window.dispatchEvent(new MessageEvent('message', {
                    data: { type: 'navigate-to-route', path: '/settings/codex-micro' },
                    origin: location.origin,
                    source: window
                  }));
                  return true;
                })()
                """,
                awaitPromise: true
            )
        }
    }

    func openMicroOnboarding() {
        queue.async { [weak self] in
            guard let self, self.isReady else { return }
            self.sendRuntimeExpression(
                """
                (async () => {
                  const store = window.__keySwitchAppStore;
                  if (!store) throw new Error('Codex settings store is unavailable');

                  const entryURL = document.scripts[0]?.src;
                  if (!entryURL) throw new Error('Codex entry module is unavailable');
                  const entrySource = await (await fetch(entryURL)).text();
                  const initialName = entrySource.match(
                    /\\.\\/(app-initial-[A-Za-z0-9_-]+\\.js)/
                  )?.[1];
                  if (!initialName) throw new Error('Codex onboarding module is unavailable');

                  const initialModule = await import(new URL(initialName, entryURL).href);
                  const resetDetection = Object.values(initialModule).find(value => {
                    if (typeof value !== 'function' || value.length !== 1) return false;
                    const source = String(value);
                    const setCount = source.match(/\\.set\\(/g)?.length ?? 0;
                    return setCount === 3 &&
                      source.includes('`idle`') &&
                      source.includes('void 0') &&
                      source.includes('!1');
                  });
                  if (!resetDetection) {
                    throw new Error('Codex Micro onboarding reset is unavailable');
                  }

                  // Reset only Codex's detection/onboarding flags. Layout and
                  // user mappings remain untouched. The following connected
                  // state then follows the same first-detection path as the
                  // supported hardware and opens Codex's own setup tour.
                  resetDetection(store);

                  window.dispatchEvent(new MessageEvent('message', {
                    data: {
                      type: 'codex-micro-window-ownership-changed',
                      isOwner: true
                    },
                    origin: location.origin,
                    source: window
                  }));

                  window.dispatchEvent(new MessageEvent('message', {
                    data: {
                      type: 'codex-micro-device-state-changed',
                      state: {
                        status: 'connected',
                        transport: 'usb',
                        model: 'codex-micro',
                        error: null,
                        battery: null
                      },
                      cause: 'keyswitch-first-run'
                    },
                    origin: location.origin,
                    source: window
                  }));
                  return true;
                })()
                """,
                awaitPromise: true
            )
            self.focusCodexWindow()
        }
    }

    func setSingleTapAgentKeys(_ enabled: Bool) {
        queue.async { [weak self] in
            self?.sendRuntimeExpression(
                """
                (async () => {
                  const store = window.__keySwitchAppStore;
                  if (!store) throw new Error('Codex settings store is unavailable');

                  const entryURL = document.scripts[0]?.src;
                  if (!entryURL) throw new Error('Codex entry module is unavailable');
                  const entrySource = await (await fetch(entryURL)).text();
                  const initialName = entrySource.match(
                    /\\.\\/(app-initial-[A-Za-z0-9_-]+\\.js)/
                  )?.[1];
                  if (!initialName) throw new Error('Codex settings module is unavailable');

                  const initialModule = await import(new URL(initialName, entryURL).href);
                  const registry = Object.values(initialModule).find(value =>
                    value?.singleTapAgentKeys?.key ===
                      'codex-micro-single-tap-agent-keys'
                  );
                  if (!registry) throw new Error('Codex Micro settings are unavailable');

                  const writer = Object.values(initialModule).find(value => {
                    if (typeof value !== 'function' || value.length !== 4) return false;
                    const source = String(value);
                    return source.includes('.query.snapshot(') &&
                      source.includes('configuredValues') &&
                      source.includes('.invalidate()');
                  });
                  if (!writer) throw new Error('Codex settings writer is unavailable');

                  // This is the same optimistic settings update used by the
                  // official Codex Micro settings screen. It updates the live
                  // renderer store and then persists the atom in the main app.
                  await writer(store, registry.singleTapAgentKeys, \(enabled));
                  return window.__keySwitchSingleTapReaderV3?.() ?? \(enabled);
                })()
                """,
                awaitPromise: true
            )
        }
    }

    func focusCodexWindow() {
        queue.async { [weak self] in
            guard let self, self.isReady else { return }

            // Hardware Agent Keys are handled by Codex's main process, which
            // raises the window on a double tap (or a configured single tap).
            // KeySwitch injects the equivalent event into the renderer, so it
            // must explicitly reproduce that final window-focus step.
            self.sendRuntimeExpression(
                """
                (() => {
                  window.focus();
                  return true;
                })()
                """
            )

            DispatchQueue.main.async {
                let applications = NSRunningApplication.runningApplications(
                    withBundleIdentifier: "com.openai.codex"
                )
                let target = applications
                    .filter { !$0.isTerminated }
                    .max {
                        ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast)
                    }
                target?.unhide()
                _ = target?.activate(options: [.activateAllWindows])
            }
        }
    }

    private func beginConnection() {
        connectionAttempt += 1
        let attempt = connectionAttempt
        cancelScheduledReconnect()
        disconnectInternal(updateStatus: false)
        publishStatus(.connecting)
        discoverRenderer(attempt: attempt)
    }

    private func discoverRenderer(attempt: Int) {
        guard let url = CodexBridgeEndpointPolicy.discoveryURL(debugPort: debugPort) else {
            handleConnectionFailure(attempt: attempt)
            return
        }

        let request = BoundedDiscoveryRequest(
            maximumResponseBytes: CodexBridgeEndpointPolicy.maximumDiscoveryResponseBytes
        )
        let requestIdentifier = ObjectIdentifier(request)
        discoveryRequest = request
        request.start(url: url) { [weak self] data, response, error in
            guard let self else { return }
            self.queue.async {
                if self.discoveryRequest.map(ObjectIdentifier.init) == requestIdentifier {
                    self.discoveryRequest = nil
                }
                guard attempt == self.connectionAttempt, self.shouldReconnect else { return }
                guard error == nil,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      CodexBridgeEndpointPolicy.isExpectedDiscoveryResponseURL(
                        httpResponse.url,
                        debugPort: self.debugPort
                      ) else {
                    self.handleConnectionFailure(attempt: attempt)
                    return
                }

                do {
                    let targets = try JSONDecoder().decode([CodexDebugTarget].self, from: data ?? Data())
                    guard let target = targets.first(where: { $0.url == "app://-/index.html" }),
                          let socketURL = CodexBridgeEndpointPolicy.validatedWebSocketURL(
                            target.webSocketDebuggerUrl,
                            debugPort: self.debugPort
                          ) else {
                        self.handleConnectionFailure(attempt: attempt)
                        return
                    }
                    self.openSocket(socketURL, attempt: attempt)
                } catch {
                    self.handleConnectionFailure(attempt: attempt)
                }
            }
        }
    }

    private func openSocket(_ url: URL, attempt: Int) {
        guard attempt == connectionAttempt, shouldReconnect else { return }
        let task = webSocketSession.webSocketTask(with: url)
        socket = task
        task.resume()
        isReady = true
        cancelScheduledReconnect()
        receiveMessages(on: task)
        sendConnectedState()
        startLightingPolling()
        publishStatus(.connected)
    }

    private func receiveMessages(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard self.socket === task else { return }
                switch result {
                case .success(let message):
                    self.handleProtocolMessage(message)
                    self.receiveMessages(on: task)
                case .failure:
                    self.disconnectInternal(updateStatus: true)
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handleConnectionFailure(attempt: Int) {
        guard attempt == connectionAttempt else { return }
        disconnectInternal(updateStatus: true)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard shouldReconnect, reconnectWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWorkItem = nil
            guard self.shouldReconnect else { return }
            self.beginConnection()
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    private func cancelScheduledReconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
    }

    private func disconnectInternal(updateStatus: Bool) {
        isReady = false
        stopLightingPolling()
        pendingResponses.removeAll()
        layoutSnapshot = nil
        discoveryRequest?.cancel()
        discoveryRequest = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        if updateStatus {
            lightingSnapshot = .off
            publishStatus(.disconnected)
            publishLighting(.off)
        }
    }

    private func handleProtocolMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let receivedData):
            data = receivedData
        case .string(let string):
            guard let encoded = string.data(using: .utf8) else { return }
            data = encoded
        @unknown default:
            return
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? Int,
              let completion = pendingResponses.removeValue(forKey: id) else {
            return
        }

        let commandResult = object["result"] as? [String: Any]
        let runtimeResult = commandResult?["result"] as? [String: Any]
        completion(runtimeResult?["value"])
    }

    private func startLightingPolling() {
        stopLightingPolling()
        pollAgentLighting()
        pollMicroLayout()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + .milliseconds(CodexBridgePollingPolicy.lightingIntervalMilliseconds),
            repeating: .milliseconds(CodexBridgePollingPolicy.lightingIntervalMilliseconds),
            leeway: .milliseconds(100)
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.pollAgentLighting()
            self.lightingPollTick += 1
            if CodexBridgePollingPolicy.shouldPollLayout(onLightingTick: self.lightingPollTick) {
                self.pollMicroLayout()
            }
        }
        timer.resume()
        lightingPollTimer = timer
    }

    private func stopLightingPolling() {
        lightingPollTimer?.cancel()
        lightingPollTimer = nil
        lightingPollIsInFlight = false
        layoutPollIsInFlight = false
        lightingPollTick = 0
    }

    private func pollAgentLighting() {
        guard isReady, !lightingPollIsInFlight else { return }
        lightingPollIsInFlight = true

        let sent = sendRuntimeExpression(
            Self.agentLightingExpression,
            awaitPromise: true,
            userGesture: false
        ) { [weak self] value in
            guard let self else { return }
            self.lightingPollIsInFlight = false
            guard let value, !(value is NSNull),
                  JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let snapshot = try? JSONDecoder().decode(CodexLightingSnapshot.self, from: data) else {
                return
            }
            guard snapshot != self.lightingSnapshot else { return }
            self.lightingSnapshot = snapshot
            self.publishLighting(snapshot)
        }

        if !sent {
            lightingPollIsInFlight = false
        }
    }

    private func pollMicroLayout() {
        guard isReady, !layoutPollIsInFlight else { return }
        layoutPollIsInFlight = true

        let sent = sendRuntimeExpression(
            Self.microLayoutExpression,
            awaitPromise: true,
            userGesture: false
        ) { [weak self] value in
            guard let self else { return }
            self.layoutPollIsInFlight = false
            guard let value, !(value is NSNull),
                  JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let snapshot = try? JSONDecoder().decode(
                    CodexMicroLayoutSnapshot.self,
                    from: data
                  ) else {
                return
            }
            guard snapshot != self.layoutSnapshot else { return }
            self.layoutSnapshot = snapshot
            self.publishLayout(snapshot)
        }

        if !sent {
            layoutPollIsInFlight = false
        }
    }

    private func sendConnectedState() {
        sendRuntimeExpression(
            """
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
                  type: 'codex-micro-window-ownership-changed',
                  isOwner: true
                },
                origin: location.origin,
                source: window
              }));
              window.dispatchEvent(new MessageEvent('message', {
                data: {
                  type: 'codex-micro-device-state-changed',
                  state,
                  cause: 'keyswitch-app'
                },
                origin: location.origin,
                source: window
              }));
              return true;
            })()
            """
        )
    }

    private func send(_ event: CodexMicroKeyEvent) {
        guard isReady else { return }
        do {
            let eventData = try JSONEncoder().encode(event)
            guard let eventJSON = String(data: eventData, encoding: .utf8) else { return }
            sendRuntimeExpression(
                """
                (() => {
                  const event = \(eventJSON);
                  if (event.slot != null) {
                    try {
                      const lighting = window.__keySwitchAppStore?.get(
                        window.__keySwitchLightingSignal
                      );
                      const liveSlot = lighting?.slots?.find(
                        slot => slot.id === event.slot
                      );
                      event.threadKey = liveSlot?.threadKey ?? event.threadKey;
                    } catch {}
                  }
                  window.dispatchEvent(new MessageEvent('message', {
                    data: { type: 'codex-micro-hid-event', event },
                    origin: location.origin,
                    source: window
                  }));
                  return true;
                })()
                """
            )
        } catch {
            publishStatus(.disconnected)
        }
    }

    private func sendJoystick(_ event: CodexMicroJoystickEvent) {
        guard isReady else { return }
        do {
            let eventData = try JSONEncoder().encode(event)
            guard let eventJSON = String(data: eventData, encoding: .utf8) else { return }
            sendRuntimeExpression(
                """
                (() => {
                  const event = \(eventJSON);
                  window.dispatchEvent(new MessageEvent('message', {
                    data: { type: 'codex-micro-joystick-event', event },
                    origin: location.origin,
                    source: window
                  }));
                  return true;
                })()
                """
            )
        } catch {
            disconnectInternal(updateStatus: true)
            scheduleReconnect()
        }
    }

    @discardableResult
    private func sendRuntimeExpression(
        _ expression: String,
        awaitPromise: Bool = false,
        userGesture: Bool = true,
        completion: ProtocolCompletion? = nil
    ) -> Bool {
        sendProtocolMessage(
            method: "Runtime.evaluate",
            params: [
                "expression": expression,
                "awaitPromise": awaitPromise,
                "returnByValue": true,
                "userGesture": userGesture,
            ],
            completion: completion
        )
    }

    @discardableResult
    private func sendProtocolMessage(
        method: String,
        params: [String: Any],
        completion: ProtocolCompletion? = nil
    ) -> Bool {
        guard isReady, let socket else { return false }

        let requestID = nextRequestID
        nextRequestID += 1

        let message: [String: Any] = [
            "id": requestID,
            "method": method,
            "params": params,
        ]

        if let completion {
            pendingResponses[requestID] = completion
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            guard let json = String(data: data, encoding: .utf8) else {
                pendingResponses.removeValue(forKey: requestID)
                return false
            }
            socket.send(.string(json)) { [weak self] error in
                guard error != nil, let self else { return }
                self.queue.async {
                    self.disconnectInternal(updateStatus: true)
                    self.scheduleReconnect()
                }
            }
            return true
        } catch {
            pendingResponses.removeValue(forKey: requestID)
            disconnectInternal(updateStatus: true)
            scheduleReconnect()
            return false
        }
    }

    private func publishStatus(_ status: BridgeStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatusChange?(status)
        }
    }

    private func publishLighting(_ snapshot: CodexLightingSnapshot) {
        DispatchQueue.main.async { [weak self] in
            self?.onLightingChange?(snapshot)
        }
    }

    private func publishLayout(_ snapshot: CodexMicroLayoutSnapshot) {
        DispatchQueue.main.async { [weak self] in
            self?.onLayoutChange?(snapshot)
        }
    }

    private static let microLayoutExpression = #"""
    (async () => {
      function isLayout(value) {
        if (!value || typeof value !== 'object' || !value.slots) return false;
        const requiredSlots = [
          'ACT06', 'ACT07', 'ACT08', 'ACT09',
          'ACT10', 'ACT11', 'ACT10_ACT11', 'ACT12'
        ];
        return requiredSlots.every(slot => value.slots[slot]?.keycapId != null);
      }

      function normalizeAgentSource(value) {
        return ['recent', 'pinned', 'priority', 'custom'].includes(value)
          ? value
          : 'recent';
      }

      function serialize(value, agentSource, singleTapAgentKeys) {
        const slots = {};
        for (const slot of [
          'ACT06', 'ACT07', 'ACT08', 'ACT09',
          'ACT10', 'ACT11', 'ACT10_ACT11', 'ACT12'
        ]) {
          slots[slot] = { keycapId: String(value.slots[slot].keycapId) };
        }
        return {
          version: Number.isFinite(value.version) ? value.version : 1,
          slots,
          encoderMode: value.encoderMode ?? 'composer-navigation',
          voiceButtonMode: value.voiceButtonMode ?? 'push-to-talk',
          separateMicrophoneKeys: !!value.separateMicrophoneKeys,
          agentSource: normalizeAgentSource(agentSource),
          singleTapAgentKeys: !!singleTapAgentKeys
        };
      }

      try {
        const cachedLayoutReader = window.__keySwitchLayoutReaderV3;
        const cachedAgentSourceReader = window.__keySwitchAgentSourceReaderV3;
        const cachedSingleTapReader = window.__keySwitchSingleTapReaderV3;
        if (typeof cachedLayoutReader === 'function') {
          const cachedValue = cachedLayoutReader();
          const cachedAgentSource = typeof cachedAgentSourceReader === 'function'
            ? cachedAgentSourceReader()
            : 'recent';
          const cachedSingleTap = typeof cachedSingleTapReader === 'function'
            ? cachedSingleTapReader()
            : false;
          if (isLayout(cachedValue)) {
            return serialize(cachedValue, cachedAgentSource, cachedSingleTap);
          }
        }
      } catch {
        delete window.__keySwitchLayoutReaderV3;
        delete window.__keySwitchAgentSourceReaderV3;
        delete window.__keySwitchSingleTapReaderV3;
      }

      const store = window.__keySwitchAppStore;
      if (!store) return null;

      const entryURL = document.scripts[0]?.src;
      if (!entryURL) return null;
      const entrySource = await (await fetch(entryURL)).text();
      const initialName = entrySource.match(
        /\.\/(app-initial-[A-Za-z0-9_-]+\.js)/
      )?.[1];
      if (!initialName) return null;

      const initialURL = new URL(initialName, entryURL).href;
      const initialModule = await import(initialURL);
      const registry = Object.values(initialModule).find(value =>
        value?.layout?.key === 'codex-micro-layout' &&
        value?.agentSource?.key === 'codex-micro-agent-source' &&
        value?.singleTapAgentKeys?.key === 'codex-micro-single-tap-agent-keys'
      );
      if (!registry) return null;

      const readerPattern = /^function\s+\w+\((\w+),(\w+)\)\s*\{\s*return\s+\1\(\w+,\2\)\s*\}$/;
      const candidates = Object.values(initialModule).filter(value =>
        typeof value === 'function' &&
        value.length === 2 &&
        readerPattern.test(String(value))
      );

      for (const candidate of candidates) {
        try {
          const value = candidate(store.get, registry.layout);
          if (!isLayout(value)) continue;

          let agentSource = 'recent';
          try {
            const source = candidate(store.get, registry.agentSource);
            if (['recent', 'pinned', 'priority', 'custom'].includes(source)) {
              agentSource = source;
            }
          } catch {}

          let singleTapAgentKeys = false;
          try {
            const enabled = candidate(store.get, registry.singleTapAgentKeys);
            if (typeof enabled === 'boolean') singleTapAgentKeys = enabled;
          } catch {}

          window.__keySwitchLayoutReaderV3 = () => candidate(store.get, registry.layout);
          window.__keySwitchAgentSourceReaderV3 = () =>
            candidate(store.get, registry.agentSource);
          window.__keySwitchSingleTapReaderV3 = () =>
            candidate(store.get, registry.singleTapAgentKeys);
          return serialize(value, agentSource, singleTapAgentKeys);
        } catch {}
      }
      return null;
    })()
    """#

    private static let agentLightingExpression = #"""
    (async () => {
      function serialize(value) {
        return {
          brightness: Number.isFinite(value.brightness) ? value.brightness : 1,
          inactivityTimeoutMs: Number.isFinite(value.inactivityTimeoutMs)
            ? value.inactivityTimeoutMs
            : 180000,
          slots: value.slots.map(slot => ({
            id: slot.id,
            title: slot.title ?? null,
            threadKey: slot.threadKey ?? null,
            status: slot.status,
            selected: !!slot.selected
          }))
        };
      }

      try {
        const cachedStore = window.__keySwitchAppStore;
        const cachedSignal = window.__keySwitchLightingSignal;
        const cachedValue = cachedStore?.get(cachedSignal);
        if (Array.isArray(cachedValue?.slots)) return serialize(cachedValue);
      } catch {
        delete window.__keySwitchAppStore;
        delete window.__keySwitchLightingSignal;
      }

      const entryURL = document.scripts[0]?.src;
      if (!entryURL) return null;
      const entrySource = await (await fetch(entryURL)).text();
      const initialName = entrySource.match(/\.\/(app-initial-[A-Za-z0-9_-]+\.js)/)?.[1];
      if (!initialName) return null;
      const initialURL = new URL(initialName, entryURL).href;
      const initialSource = await (await fetch(initialURL)).text();
      const moduleName = initialSource.match(
        /\.\/(codex-micro-slot-signals-[A-Za-z0-9_-]+\.js)/
      )?.[1];
      if (!moduleName) return null;

      const signalModule = await import(new URL(moduleName, initialURL).href);
      const signals = Object.values(signalModule).filter(signal => {
        try { return signal?.scope?.__scopeBrand === "AppScope"; }
        catch { return false; }
      });

      const root = window.__codexRoot?._internalRoot?.current;
      if (!root) return null;
      const stores = new Set();
      const seenObjects = new WeakSet();
      const skippedKeys = new Set(["return", "child", "sibling", "stateNode", "_owner"]);

      function inspect(value, depth) {
        if (!value || (typeof value !== "object" && typeof value !== "function")) return;
        if (seenObjects.has(value)) return;
        seenObjects.add(value);
        try {
          if (
            typeof value.get === "function" &&
            typeof value.watch === "function" &&
            value.scope?.__scopeBrand === "AppScope"
          ) stores.add(value);
        } catch {}
        if (depth <= 0) return;

        let descriptors;
        try { descriptors = Object.getOwnPropertyDescriptors(value); }
        catch { return; }
        for (const [key, descriptor] of Object.entries(descriptors)) {
          if (skippedKeys.has(key) || !("value" in descriptor)) continue;
          inspect(descriptor.value, depth - 1);
        }
      }

      const fibers = [root];
      const seenFibers = new Set();
      while (fibers.length) {
        const fiber = fibers.pop();
        if (!fiber || seenFibers.has(fiber)) continue;
        seenFibers.add(fiber);
        inspect(fiber.memoizedState, 10);
        inspect(fiber.memoizedProps, 5);
        inspect(fiber.dependencies, 7);
        if (fiber.child) fibers.push(fiber.child);
        if (fiber.sibling) fibers.push(fiber.sibling);
      }

      for (const store of stores) {
        for (const signal of signals) {
          try {
            const value = store.get(signal);
            if (!Array.isArray(value?.slots) || value.slots.length !== 6) continue;
            window.__keySwitchAppStore = store;
            window.__keySwitchLightingSignal = signal;
            return serialize(value);
          } catch {}
        }
      }
      return null;
    })()
    """#
}
