import AppKit
import Foundation
import Observation

struct AgentTapTracker {
    static let doubleTapInterval: TimeInterval = 0.35

    private var lastTap: (control: MicroControl, threadKey: String?, timestamp: TimeInterval)?

    mutating func shouldFocusCodex(
        for control: MicroControl,
        threadKey: String?,
        timestamp: TimeInterval,
        focusOnSingleTap: Bool
    ) -> Bool {
        guard control.isAgentKey else { return false }

        if focusOnSingleTap {
            lastTap = nil
            return true
        }

        if let lastTap,
           lastTap.control == control,
           lastTap.threadKey == threadKey,
           timestamp >= lastTap.timestamp,
           timestamp - lastTap.timestamp <= Self.doubleTapInterval {
            self.lastTap = nil
            return true
        }

        lastTap = (control, threadKey, timestamp)
        return false
    }
}

/// The subset of persisted settings that changes how the global event tap
/// interprets keyboard input. Keeping this value separate prevents visual,
/// connection, and onboarding preferences from needlessly rebuilding the
/// keyboard engine (which also deactivates an active layer for safety).
struct KeyboardEngineConfigurationSignature: Equatable {
    let activationMode: ActivationMode
    let activationShortcut: ActivationShortcut
    let blockUnmappedKeys: Bool
    let bindings: [KeyBinding]

    init(configuration: AppConfiguration) {
        activationMode = configuration.activationMode
        activationShortcut = configuration.activationShortcut
        blockUnmappedKeys = configuration.blockUnmappedKeys
        bindings = configuration.bindings
    }
}

enum CodexSetupReconnectAction: Equatable {
    case none
    case showKeySwitch
    case openMicroOnboarding
}

struct CodexSetupRelaunchPolicy {
    /// Codex starts without taking focus while KeySwitch shows connection
    /// progress. The official Micro onboarding receives focus only after the
    /// user explicitly chooses the final setup action.
    static let activatesCodexOnLaunch = false
    static let reconnectTimeoutNanoseconds: UInt64 = 20_000_000_000

    static func reconnectAction(openMicroOnboarding: Bool) -> CodexSetupReconnectAction {
        openMicroOnboarding ? .openMicroOnboarding : .showKeySwitch
    }
}

struct PermissionOnboardingPolicy {
    static func shouldRestoreSetup(
        previouslyGranted: Bool,
        currentlyGranted: Bool,
        hasCompletedFirstRunSetup: Bool
    ) -> Bool {
        !previouslyGranted
            && currentlyGranted
            && !hasCompletedFirstRunSetup
    }
}

@MainActor
@Observable
final class AppModel {
    @ObservationIgnored let updater: any UpdaterProviding

    var configuration: AppConfiguration {
        didSet {
            configurationDidChange(from: oldValue)
        }
    }

    var layerIsActive = false
    var pressedControls: Set<MicroControl> = []
    var bridgeStatus: BridgeStatus = .disconnected
    var eventTapIsActive = false
    var permissions = PermissionService.snapshot()
    var lastActionDescription = "Waiting for input"
    var dialRotationStep = 0
    var lightingSnapshot = CodexLightingSnapshot.off
    var codexMicroLayout = CodexMicroLayoutSnapshot.codexDefault
    var hasLiveCodexMicroLayout = false
    var hudLightingIsDimmed = false
    var hudPreviewIsVisible = false
    var codexRelaunchIsInProgress = false
    var setupErrorMessage: String?
    var launchAtLoginState = LaunchAtLoginService.currentState
    var launchAtLoginErrorMessage: String?

    /// Readiness requires both the current macOS grant and a live event tap.
    /// A tap can briefly survive after its permission is manually revoked, so
    /// it must never be used as a substitute for the grant itself.
    var keyboardAccessIsReady: Bool {
        permissions.keyboardAccessIsReady(eventTapIsActive: eventTapIsActive)
    }

    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var permissionRefreshTimer: Timer?
    @ObservationIgnored private var autoDimTimer: Timer?
    @ObservationIgnored private var layerAutoExitTimer: Timer?
    @ObservationIgnored private var hudPreviewDismissTask: Task<Void, Never>?
    @ObservationIgnored private var agentTapTracker = AgentTapTracker()
    @ObservationIgnored private var codexSetupReconnectAction = CodexSetupReconnectAction.none
    @ObservationIgnored private var codexSetupTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var codexSetupSessionID = 0

    @ObservationIgnored
    private lazy var bridge: CodexMicroBridge = {
        let bridge = CodexMicroBridge(debugPort: configuration.debugPort)
        bridge.onStatusChange = { [weak self] status in
            guard let self else { return }
            self.bridgeStatus = status
            if status != .connected {
                self.hasLiveCodexMicroLayout = false
            } else {
                let reconnectAction = self.codexSetupReconnectAction
                self.codexSetupReconnectAction = .none
                self.cancelCodexSetupTimeout()
                switch reconnectAction {
                case .none:
                    break
                case .showKeySwitch:
                    self.codexRelaunchIsInProgress = false
                    self.setupWindowController.show()
                case .openMicroOnboarding:
                    self.codexRelaunchIsInProgress = false
                    self.beginCodexMicroSetup()
                }
            }
        }
        bridge.onLightingChange = { [weak self] snapshot in
            #if DEBUG
            guard ProcessInfo.processInfo.environment["KEYSWITCH_PREVIEW_LIGHTS"] != "1" else {
                return
            }
            #endif
            guard let self else { return }
            let changed = self.lightingSnapshot != snapshot
            if changed {
                self.lightingSnapshot = snapshot
                self.noteLightingActivity()
            }
        }
        bridge.onLayoutChange = { [weak self] layout in
            guard let self else { return }
            self.codexMicroLayout = layout
            self.hasLiveCodexMicroLayout = true
            if self.configuration.focusCodexOnSingleTap != layout.singleTapAgentKeys {
                self.configuration.focusCodexOnSingleTap = layout.singleTapAgentKeys
            }
        }
        return bridge
    }()

    @ObservationIgnored
    private lazy var keyboardEngine: KeyboardEngine = {
        let engine = KeyboardEngine(configuration: engineConfiguration)
        engine.onLayerStateChanged = { [weak self] active in
            Task { @MainActor [weak self] in
                self?.handleLayerStateChanged(active)
            }
        }
        engine.onControlEvent = { [weak self] control, action in
            guard let self else { return }
            let threadKey = control.slot.flatMap {
                self.lightingSnapshot.light(for: $0).threadKey
            }
            let shouldFocusCodex = action == 1 && self.agentTapTracker.shouldFocusCodex(
                for: control,
                threadKey: threadKey,
                timestamp: ProcessInfo.processInfo.systemUptime,
                focusOnSingleTap: self.configuration.focusCodexOnSingleTap
            )
            self.sendControlToCodex(control, action: action)
            if shouldFocusCodex {
                self.bridge.focusCodexWindow()
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleControlEvent(control, action: action)
            }
        }
        engine.onTapStatusChanged = { [weak self] active in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let snapshot = PermissionService.snapshot()
                self.permissions = snapshot
                self.eventTapIsActive = active && snapshot.accessibilityGranted

                if active, !snapshot.accessibilityGranted {
                    self.keyboardEngine.stop()
                }
            }
        }
        return engine
    }()

    @ObservationIgnored
    private lazy var hudController = HUDWindowController(model: self)

    @ObservationIgnored
    private lazy var setupWindowController = FirstRunSetupWindowController(model: self)

    init(updater: (any UpdaterProviding)? = nil) {
        self.updater = updater ?? UpdateControllerFactory.make()
        configuration = Self.loadConfiguration()
        #if DEBUG
        if ProcessInfo.processInfo.environment["KEYSWITCH_PREVIEW_LIGHTS"] == "1" {
            lightingSnapshot = .preview
        }
        #endif
        DispatchQueue.main.async { [weak self] in
            self?.start()
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        permissions = PermissionService.snapshot()
        refreshLaunchAtLoginState()
        eventTapIsActive = permissions.accessibilityGranted
            ? keyboardEngine.start()
            : false
        bridge.connect()
        startPermissionRefreshTimer()

        #if DEBUG
        let shouldForceSetup = ProcessInfo.processInfo.environment["KEYSWITCH_SHOW_SETUP"] == "1"
        #else
        let shouldForceSetup = false
        #endif

        if !configuration.hasCompletedFirstRunSetup || shouldForceSetup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.setupWindowController.show()
            }
        }

        updateHUDVisibility()

        #if DEBUG
        if ProcessInfo.processInfo.environment["KEYSWITCH_PREVIEW_HUD"] == "1" {
            keyboardEngine.toggleLayerFromMenu()
        }
        #endif
    }

    func stop() {
        keyboardEngine.stop()
        bridge.disconnect()
        hudController.hide()
        stopPermissionRefreshTimer()
        stopAutoDimTimer()
        stopLayerAutoExitTimer()
        stopHUDPreview()
        cancelPendingCodexSetup(clearError: false)
        hasStarted = false
    }

    func toggleLayerFromMenu() {
        keyboardEngine.toggleLayerFromMenu()
    }

    func deactivateLayer() {
        keyboardEngine.deactivateLayer()
    }

    @discardableResult
    func beginActivationShortcutCapture(
        onCapture: @escaping (PhysicalKey, Set<ActivationModifier>) -> Void,
        onCancel: @escaping () -> Void
    ) -> Bool {
        guard keyboardAccessIsReady else { return false }

        return keyboardEngine.beginShortcutCapture(
            onCapture: { key, modifiers in
                Task { @MainActor in
                    onCapture(key, modifiers)
                }
            },
            onCancel: {
                Task { @MainActor in
                    onCancel()
                }
            }
        )
    }

    func endActivationShortcutCapture() {
        keyboardEngine.cancelShortcutCapture()
    }

    func retryKeyboardAccess() {
        PermissionService.request()
        permissions = PermissionService.snapshot()
        keyboardEngine.stop()
        eventTapIsActive = permissions.accessibilityGranted
            ? keyboardEngine.start()
            : false
        startPermissionRefreshTimer()
    }

    func openNextRequiredKeyboardPermission() {
        guard let kind = PermissionService.nextRequiredPermission(in: permissions) else {
            retryKeyboardAccess()
            return
        }
        PermissionService.openSettings(for: kind)
    }

    func refreshPermissions() {
        refreshPermissionState(retryIfGranted: true)
    }

    func refreshLaunchAtLoginState() {
        launchAtLoginState = LaunchAtLoginService.currentState
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginErrorMessage = nil
        do {
            try LaunchAtLoginService.setEnabled(enabled)
        } catch {
            launchAtLoginErrorMessage = error.localizedDescription
        }
        refreshLaunchAtLoginState()
    }

    func openLoginItemsSettings() {
        LaunchAtLoginService.openSystemSettings()
    }

    func reconnectBridge() {
        bridge.reconnect(debugPort: configuration.debugPort)
    }

    func openCodexMicroSettings() {
        bridge.openMicroSettings()
    }

    func showFirstRunSetup() {
        setupErrorMessage = nil
        setupWindowController.show()
    }

    func deferFirstRunSetup() {
        PermissionService.dismissPermissionGuide()
        cancelPendingCodexSetup(clearError: true)
        setupWindowController.hide()
    }

    func firstRunSetupWindowDidClose() {
        PermissionService.dismissPermissionGuide()
        cancelPendingCodexSetup(clearError: true)
    }

    func completeFirstRunSetup() {
        PermissionService.dismissPermissionGuide()
        cancelPendingCodexSetup(clearError: true)
        configuration.hasCompletedFirstRunSetup = true
        setupWindowController.hide()
    }

    func beginCodexMicroSetup() {
        guard bridgeStatus == .connected else {
            restartCodexAndBeginSetup()
            return
        }

        setupErrorMessage = nil
        codexSetupSessionID += 1
        let sessionID = codexSetupSessionID
        codexRelaunchIsInProgress = true
        bridge.openMicroOnboarding { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, sessionID == self.codexSetupSessionID else { return }
                self.codexRelaunchIsInProgress = false
                switch result {
                case .success:
                    self.completeFirstRunSetup()
                    self.bridge.focusCodexWindow()
                case .failure(let error):
                    self.setupErrorMessage = error.localizedDescription
                    self.setupWindowController.show()
                }
            }
        }
    }

    func restartCodexAndBeginSetup() {
        restartCodex(openSetupAfterReconnect: true)
    }

    func connectCodexForSetup() {
        restartCodex(openSetupAfterReconnect: false)
    }

    private func restartCodex(openSetupAfterReconnect: Bool) {
        guard !codexRelaunchIsInProgress else { return }

        cancelCodexSetupTimeout()
        codexSetupSessionID += 1
        let sessionID = codexSetupSessionID
        setupErrorMessage = nil
        codexRelaunchIsInProgress = true
        codexSetupReconnectAction = CodexSetupRelaunchPolicy.reconnectAction(
            openMicroOnboarding: openSetupAfterReconnect
        )

        let runningCodexApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.openai.codex"
        ).filter { !$0.isTerminated }

        for application in runningCodexApps {
            _ = application.terminate()
        }

        waitForCodexToTerminate(
            runningCodexApps,
            attemptsRemaining: 40,
            sessionID: sessionID
        )
    }

    func binding(for control: MicroControl) -> KeyBinding {
        configuration.bindings.first(where: { $0.control == control })
            ?? KeyBinding(control: control, physicalKey: nil)
    }

    func keycap(for control: MicroControl) -> MicroKeycap {
        codexMicroLayout.keycap(for: control) ?? .defaultValue(for: control)
    }

    var effectiveLightingBrightness: Double {
        guard !hudLightingIsDimmed else { return 0 }
        return min(max(lightingSnapshot.brightness, 0), 1)
    }

    var effectiveHUDAppearance: HUDAppearance {
        #if DEBUG
        if let previewValue = ProcessInfo.processInfo.environment["KEYSWITCH_PREVIEW_APPEARANCE"],
           let previewAppearance = HUDAppearance(rawValue: previewValue) {
            return previewAppearance
        }
        #endif
        return configuration.hudAppearance
    }

    var effectiveExpandedHUDSize: ExpandedHUDSize {
        #if DEBUG
        if let previewValue = ProcessInfo.processInfo.environment["KEYSWITCH_PREVIEW_HUD_SIZE"],
           let previewSize = ExpandedHUDSize(rawValue: previewValue) {
            return previewSize
        }
        #endif
        return configuration.expandedHUDSize
    }

    func light(for control: MicroControl) -> AgentLightState? {
        guard let slot = control.slot else { return nil }
        return lightingSnapshot.light(for: slot)
    }

    func assign(_ key: PhysicalKey?, to control: MicroControl) {
        var bindings = configuration.bindings

        if let key {
            for index in bindings.indices where bindings[index].control != control {
                if bindings[index].physicalKey?.id == key.id {
                    bindings[index].physicalKey = nil
                }
            }
        }

        if let index = bindings.firstIndex(where: { $0.control == control }) {
            bindings[index].physicalKey = key
        } else {
            bindings.append(KeyBinding(control: control, physicalKey: key))
        }

        configuration.bindings = bindings
    }

    func resetMappings() {
        configuration.bindings = KeyBinding.defaults
    }

    private var engineConfiguration: KeyboardEngineConfiguration {
        KeyboardEngineConfiguration(
            activationMode: configuration.activationMode,
            activationShortcut: configuration.activationShortcut,
            blockUnmappedKeys: configuration.blockUnmappedKeys,
            bindings: configuration.bindings
        )
    }

    private func handleLayerStateChanged(_ active: Bool) {
        layerIsActive = active
        if !active {
            pressedControls.removeAll()
            stopLayerAutoExitTimer()
            updateHUDVisibility()
            return
        }
        noteLightingActivity()
        restartLayerAutoExitTimer()
        updateHUDVisibility()
    }

    private func handleControlEvent(_ control: MicroControl, action: Int) {
        noteLightingActivity()
        if control == .dialPrevious || control == .dialNext {
            if action == 1 {
                let delta = control == .dialPrevious ? -1 : 1
                dialRotationStep = (dialRotationStep + delta + 8) % 8
                lastActionDescription = control == .dialPrevious
                    ? "Dial moved to previous item"
                    : "Dial moved to next item"
            }
            pressedControls.remove(control)
            updateLayerAutoExitTimerForControlState()
            return
        }

        if control.isStickControl {
            if action == 1 {
                pressedControls.insert(control)
            } else {
                pressedControls.remove(control)
            }
            updateLayerAutoExitTimerForControlState()
            return
        }

        if action == 1 {
            pressedControls.insert(control)
            lastActionDescription = "\(control.title) pressed"
        } else {
            pressedControls.remove(control)
            lastActionDescription = "\(control.title) released"
        }
        updateLayerAutoExitTimerForControlState()
    }

    private func sendControlToCodex(_ control: MicroControl, action: Int) {
        // KeySwitch emulates a physical Micro slot. Codex owns the action
        // assigned to that slot through its official Codex Micro settings,
        // including every analog-stick direction.
        bridge.send(control: control, action: action)
    }

    private func waitForCodexToTerminate(
        _ applications: [NSRunningApplication],
        attemptsRemaining: Int,
        sessionID: Int
    ) {
        guard sessionID == codexSetupSessionID else { return }
        if applications.allSatisfy(\.isTerminated) {
            launchOriginalCodexForBridge(sessionID: sessionID)
            return
        }

        guard attemptsRemaining > 0 else {
            failCodexSetup(
                sessionID: sessionID,
                message: "Codex did not quit. Quit it manually, then choose Set Up again."
            )
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.waitForCodexToTerminate(
                applications,
                attemptsRemaining: attemptsRemaining - 1,
                sessionID: sessionID
            )
        }
    }

    private func launchOriginalCodexForBridge(sessionID: Int) {
        guard sessionID == codexSetupSessionID else { return }
        let workspace = NSWorkspace.shared
        let fallbackURL = URL(fileURLWithPath: "/Applications/ChatGPT.app", isDirectory: true)
        let applicationURL = workspace.urlForApplication(
            withBundleIdentifier: "com.openai.codex"
        ) ?? fallbackURL

        guard FileManager.default.fileExists(atPath: applicationURL.path) else {
            failCodexSetup(
                sessionID: sessionID,
                message: "The Codex desktop app was not found in Applications."
            )
            return
        }

        let launchConfiguration = NSWorkspace.OpenConfiguration()
        launchConfiguration.arguments = [
            "--remote-debugging-address=127.0.0.1",
            "--remote-debugging-port=\(configuration.debugPort)",
            "--no-first-run",
        ]
        launchConfiguration.activates = CodexSetupRelaunchPolicy.activatesCodexOnLaunch

        workspace.openApplication(
            at: applicationURL,
            configuration: launchConfiguration
        ) { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard sessionID == self.codexSetupSessionID else { return }
                if let error {
                    self.failCodexSetup(
                        sessionID: sessionID,
                        message: "Codex could not be reopened: \(error.localizedDescription)"
                    )
                    return
                }

                self.bridge.reconnect(debugPort: self.configuration.debugPort)
                self.scheduleCodexSetupTimeout(sessionID: sessionID)
            }
        }
    }

    private func scheduleCodexSetupTimeout(sessionID: Int) {
        cancelCodexSetupTimeout()
        codexSetupTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: CodexSetupRelaunchPolicy.reconnectTimeoutNanoseconds
                )
            } catch {
                return
            }
            guard let self,
                  sessionID == self.codexSetupSessionID,
                  self.codexSetupReconnectAction != .none else {
                return
            }
            self.failCodexSetup(
                sessionID: sessionID,
                message: "Codex opened, but KeySwitch could not verify the local connection. Check that port \(self.configuration.debugPort) is available, then try again."
            )
        }
    }

    private func failCodexSetup(sessionID: Int, message: String) {
        guard sessionID == codexSetupSessionID else { return }
        cancelCodexSetupTimeout()
        codexSetupReconnectAction = .none
        codexRelaunchIsInProgress = false
        setupErrorMessage = message
        setupWindowController.show()
    }

    private func cancelPendingCodexSetup(clearError: Bool) {
        codexSetupSessionID += 1
        cancelCodexSetupTimeout()
        codexSetupReconnectAction = .none
        codexRelaunchIsInProgress = false
        if clearError {
            setupErrorMessage = nil
        }
    }

    private func cancelCodexSetupTimeout() {
        codexSetupTimeoutTask?.cancel()
        codexSetupTimeoutTask = nil
    }

    private func configurationDidChange(from previous: AppConfiguration) {
        saveConfiguration()
        let keyboardConfigurationChanged = KeyboardEngineConfigurationSignature(
            configuration: configuration
        ) != KeyboardEngineConfigurationSignature(configuration: previous)
        if hasStarted, keyboardConfigurationChanged {
            keyboardEngine.update(configuration: engineConfiguration)
        }

        if configuration.debugPort != previous.debugPort, hasStarted {
            bridge.reconnect(debugPort: configuration.debugPort)
        }
        if configuration.showHUD != previous.showHUD {
            if configuration.showHUD {
                presentHUDPreview()
            } else {
                stopHUDPreview()
                updateHUDVisibility()
            }
        }
        if configuration.hudAppearance != previous.hudAppearance {
            hudController.updateAppearance()
            presentHUDPreview()
        }
        if configuration.expandedHUDSize != previous.expandedHUDSize {
            hudController.updateSize()
            presentHUDPreview()
        }
        if configuration.activationMode != previous.activationMode
            || configuration.layerAutoExitTimeout != previous.layerAutoExitTimeout {
            updateLayerAutoExitTimerForControlState()
        }
    }

    private func updateHUDVisibility() {
        if configuration.showHUD && (layerIsActive || hudPreviewIsVisible) {
            hudController.show()
        } else {
            hudController.hide()
        }
    }

    private func presentHUDPreview() {
        guard hasStarted, configuration.showHUD else { return }

        hudPreviewDismissTask?.cancel()
        hudPreviewIsVisible = true
        noteLightingActivity()
        updateHUDVisibility()

        hudPreviewDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.hudPreviewDismissTask = nil
            self.hudPreviewIsVisible = false
            self.updateHUDVisibility()
        }
    }

    private func stopHUDPreview() {
        hudPreviewDismissTask?.cancel()
        hudPreviewDismissTask = nil
        hudPreviewIsVisible = false
    }

    private func startPermissionRefreshTimer() {
        guard permissionRefreshTimer == nil else { return }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissionState(retryIfGranted: true)
            }
        }
        permissionRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPermissionRefreshTimer() {
        permissionRefreshTimer?.invalidate()
        permissionRefreshTimer = nil
    }

    private func noteLightingActivity() {
        hudLightingIsDimmed = false
        stopAutoDimTimer()
        guard let interval = lightingSnapshot.inactivityInterval else { return }

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hudLightingIsDimmed = true
            }
        }
        autoDimTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopAutoDimTimer() {
        autoDimTimer?.invalidate()
        autoDimTimer = nil
    }

    private func updateLayerAutoExitTimerForControlState() {
        guard configuration.activationMode == .toggle,
              layerIsActive,
              pressedControls.isEmpty else {
            stopLayerAutoExitTimer()
            return
        }
        restartLayerAutoExitTimer()
    }

    private func restartLayerAutoExitTimer() {
        stopLayerAutoExitTimer()
        guard layerIsActive,
              pressedControls.isEmpty,
              let interval = effectiveLayerAutoExitInterval else { return }

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.layerIsActive else { return }
                self.stopLayerAutoExitTimer()
                self.keyboardEngine.deactivateLayer()
                self.lastActionDescription = "Layer turned off after inactivity"
            }
        }
        layerAutoExitTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private var effectiveLayerAutoExitInterval: TimeInterval? {
        guard configuration.activationMode == .toggle else { return nil }
        #if DEBUG
        if let previewValue = ProcessInfo.processInfo.environment[
            "KEYSWITCH_PREVIEW_AUTO_EXIT_SECONDS"
        ], let previewInterval = TimeInterval(previewValue), previewInterval > 0 {
            return previewInterval
        }
        #endif
        return configuration.layerAutoExitInterval
    }

    private func stopLayerAutoExitTimer() {
        layerAutoExitTimer?.invalidate()
        layerAutoExitTimer = nil
    }

    private func refreshPermissionState(retryIfGranted: Bool) {
        let previouslyGranted = permissions.accessibilityGranted
        let snapshot = PermissionService.snapshot()
        let shouldRestoreSetup = PermissionOnboardingPolicy.shouldRestoreSetup(
            previouslyGranted: previouslyGranted,
            currentlyGranted: snapshot.accessibilityGranted,
            hasCompletedFirstRunSetup: configuration.hasCompletedFirstRunSetup
        )
        permissions = snapshot

        // TCC can leave an already-created tap alive briefly after the user
        // revokes Accessibility. Stop it ourselves and make the UI reflect the
        // current grant rather than the stale tap.
        if !snapshot.accessibilityGranted {
            if previouslyGranted || eventTapIsActive {
                keyboardEngine.stop()
            }
            eventTapIsActive = false
            return
        }

        PermissionService.dismissPermissionGuide()

        if retryIfGranted, !eventTapIsActive {
            eventTapIsActive = keyboardEngine.start()
        }

        // System Settings remains frontmost while the user grants Accessibility.
        // Return an unfinished setup to the foreground once the live TCC probe
        // observes that transition, instead of leaving only the menu-bar item.
        if shouldRestoreSetup {
            setupWindowController.show()
        }
    }

    private func saveConfiguration() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: Self.configurationKey)
    }

    private static func loadConfiguration() -> AppConfiguration {
        guard let data = UserDefaults.standard.data(forKey: configurationKey),
              let configuration = try? JSONDecoder().decode(AppConfiguration.self, from: data) else {
            return .default
        }
        return configuration
    }

    private static let configurationKey = "keyswitch-configuration-v1"
}
