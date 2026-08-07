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

@MainActor
@Observable
final class AppModel {
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
    var statusHUDPillIsVisible = false
    var codexRelaunchIsInProgress = false
    var setupErrorMessage: String?

    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var permissionRefreshTimer: Timer?
    @ObservationIgnored private var autoDimTimer: Timer?
    @ObservationIgnored private var layerAutoExitTimer: Timer?
    @ObservationIgnored private var statusHUDHideTimer: Timer?
    @ObservationIgnored private var hudWindowHideTask: Task<Void, Never>?
    @ObservationIgnored private var agentTapTracker = AgentTapTracker()
    @ObservationIgnored private var shouldBeginSetupAfterReconnect = false
    @ObservationIgnored private var lastStatusHUDConnectionState: Bool?

    @ObservationIgnored
    private lazy var bridge: CodexMicroBridge = {
        let bridge = CodexMicroBridge(debugPort: configuration.debugPort)
        bridge.onStatusChange = { [weak self] status in
            guard let self else { return }
            let statusChanged = self.bridgeStatus != status
            self.bridgeStatus = status
            if status != .connected {
                self.hasLiveCodexMicroLayout = false
            } else {
                self.codexRelaunchIsInProgress = false
                if self.shouldBeginSetupAfterReconnect {
                    self.shouldBeginSetupAfterReconnect = false
                    self.beginCodexMicroSetup()
                }
            }
            if statusChanged {
                self.noteBridgeStatusHUDActivity(status)
            }
        }
        bridge.onLightingChange = { [weak self] snapshot in
            #if DEBUG
            guard ProcessInfo.processInfo.environment["KEYSWITCH_PREVIEW_LIGHTS"] != "1" else {
                return
            }
            #endif
            guard let self else { return }
            let meaningfulStatusChange = snapshot.hasMeaningfulStatusChange(
                comparedTo: self.lightingSnapshot
            )
            let changed = self.lightingSnapshot != snapshot
            self.lightingSnapshot = snapshot
            if changed {
                self.noteLightingActivity()
            }
            if meaningfulStatusChange {
                self.noteStatusHUDActivity()
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
            DispatchQueue.main.async {
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
            DispatchQueue.main.async {
                self.handleControlEvent(control, action: action)
            }
        }
        engine.onTapStatusChanged = { [weak self] active in
            DispatchQueue.main.async {
                self?.eventTapIsActive = active
                self?.permissions = PermissionService.snapshot()
            }
        }
        return engine
    }()

    @ObservationIgnored
    private lazy var hudController = HUDWindowController(model: self)

    @ObservationIgnored
    private lazy var setupWindowController = FirstRunSetupWindowController(model: self)

    init() {
        configuration = Self.loadConfiguration()
        #if DEBUG
        if ProcessInfo.processInfo.environment["KEYSWITCH_PREVIEW_LIGHTS"] == "1" {
            lightingSnapshot = .preview
        }
        if ProcessInfo.processInfo.environment["KEYSWITCH_PREVIEW_STATUS_PILL"] == "1" {
            statusHUDPillIsVisible = true
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
        eventTapIsActive = keyboardEngine.start()
        bridge.connect()

        if !permissions.allGranted || !eventTapIsActive {
            startPermissionRefreshTimer()
        }

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
        stopStatusHUDHideTimer()
        hudWindowHideTask?.cancel()
        hudWindowHideTask = nil
        hasStarted = false
    }

    func toggleLayerFromMenu() {
        keyboardEngine.toggleLayerFromMenu()
    }

    func deactivateLayer() {
        keyboardEngine.deactivateLayer()
    }

    func retryKeyboardAccess() {
        PermissionService.request()
        keyboardEngine.stop()
        eventTapIsActive = keyboardEngine.start()
        permissions = PermissionService.snapshot()
        if !permissions.allGranted || !eventTapIsActive {
            startPermissionRefreshTimer()
        }
    }

    func refreshPermissions() {
        refreshPermissionState(retryIfGranted: true)
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
        setupWindowController.hide()
    }

    func completeFirstRunSetup() {
        configuration.hasCompletedFirstRunSetup = true
        setupWindowController.hide()
        noteStatusHUDActivity()
    }

    func beginCodexMicroSetup() {
        guard bridgeStatus == .connected else {
            restartCodexAndBeginSetup()
            return
        }

        setupErrorMessage = nil
        bridge.openMicroOnboarding()
        completeFirstRunSetup()
    }

    func restartCodexAndBeginSetup() {
        restartCodex(openSetupAfterReconnect: true)
    }

    func connectCodexForSetup() {
        restartCodex(openSetupAfterReconnect: false)
    }

    private func restartCodex(openSetupAfterReconnect: Bool) {
        guard !codexRelaunchIsInProgress else { return }

        setupErrorMessage = nil
        codexRelaunchIsInProgress = true
        shouldBeginSetupAfterReconnect = openSetupAfterReconnect

        let runningCodexApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.openai.codex"
        ).filter { !$0.isTerminated }

        for application in runningCodexApps {
            _ = application.terminate()
        }

        waitForCodexToTerminate(runningCodexApps, attemptsRemaining: 40)
    }

    func setFocusCodexOnSingleTap(_ enabled: Bool) {
        configuration.focusCodexOnSingleTap = enabled
        bridge.setSingleTapAgentKeys(enabled)
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
        return min(max(configuration.lightingBrightness, 0), 1)
            * min(max(lightingSnapshot.brightness, 0), 1)
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

    var shouldDisplayStatusPill: Bool {
        guard configuration.showHUD,
              configuration.hasCompletedFirstRunSetup,
              !layerIsActive else { return false }

        #if DEBUG
        if ProcessInfo.processInfo.environment["KEYSWITCH_PREVIEW_STATUS_PILL"] == "1" {
            return true
        }
        #endif

        switch configuration.statusHUDMode {
        case .smart:
            return statusHUDPillIsVisible
        case .always:
            return true
        case .hidden:
            return false
        }
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
            noteStatusHUDActivity()
            return
        }
        if active {
            stopStatusHUDHideTimer()
            hudWindowHideTask?.cancel()
            hudWindowHideTask = nil
            noteLightingActivity()
            restartLayerAutoExitTimer()
        }
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
        attemptsRemaining: Int
    ) {
        if applications.allSatisfy(\.isTerminated) {
            launchOriginalCodexForBridge()
            return
        }

        guard attemptsRemaining > 0 else {
            codexRelaunchIsInProgress = false
            shouldBeginSetupAfterReconnect = false
            setupErrorMessage = "Codex did not quit. Quit it manually, then choose Set Up again."
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.waitForCodexToTerminate(
                applications,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func launchOriginalCodexForBridge() {
        let workspace = NSWorkspace.shared
        let fallbackURL = URL(fileURLWithPath: "/Applications/ChatGPT.app", isDirectory: true)
        let applicationURL = workspace.urlForApplication(
            withBundleIdentifier: "com.openai.codex"
        ) ?? fallbackURL

        guard FileManager.default.fileExists(atPath: applicationURL.path) else {
            codexRelaunchIsInProgress = false
            shouldBeginSetupAfterReconnect = false
            setupErrorMessage = "The Codex desktop app was not found in Applications."
            return
        }

        let launchConfiguration = NSWorkspace.OpenConfiguration()
        launchConfiguration.arguments = [
            "--remote-debugging-port=\(configuration.debugPort)",
            "--no-first-run",
        ]
        launchConfiguration.activates = true

        workspace.openApplication(
            at: applicationURL,
            configuration: launchConfiguration
        ) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.codexRelaunchIsInProgress = false
                if let error {
                    self.shouldBeginSetupAfterReconnect = false
                    self.setupErrorMessage = "Codex could not be reopened: \(error.localizedDescription)"
                    return
                }

                self.bridge.reconnect(debugPort: self.configuration.debugPort)
            }
        }
    }

    private func configurationDidChange(from previous: AppConfiguration) {
        saveConfiguration()
        if hasStarted {
            keyboardEngine.update(configuration: engineConfiguration)
        }

        if configuration.debugPort != previous.debugPort, hasStarted {
            bridge.reconnect(debugPort: configuration.debugPort)
        }
        if configuration.showHUD != previous.showHUD
            || configuration.hasCompletedFirstRunSetup != previous.hasCompletedFirstRunSetup
            || configuration.statusHUDMode != previous.statusHUDMode
            || configuration.statusHUDHideDelay != previous.statusHUDHideDelay {
            updateStatusHUDConfiguration(from: previous)
        }
        if configuration.hudAppearance != previous.hudAppearance {
            hudController.updateAppearance()
        }
        if configuration.autoDimTimeout != previous.autoDimTimeout {
            noteLightingActivity()
        }
        if configuration.layerAutoExitTimeout != previous.layerAutoExitTimeout {
            updateLayerAutoExitTimerForControlState()
        }
    }

    private func updateHUDVisibility() {
        if configuration.showHUD && (layerIsActive || shouldDisplayStatusPill) {
            hudController.show()
        } else {
            hudController.hide()
        }
    }

    private func updateStatusHUDConfiguration(from previous: AppConfiguration) {
        guard configuration.showHUD, configuration.hasCompletedFirstRunSetup else {
            concealStatusPill(animated: false)
            return
        }

        if layerIsActive {
            updateHUDVisibility()
            return
        }

        switch configuration.statusHUDMode {
        case .hidden:
            concealStatusPill(animated: false)
        case .always:
            stopStatusHUDHideTimer()
            hudWindowHideTask?.cancel()
            hudWindowHideTask = nil
            statusHUDPillIsVisible = true
            updateHUDVisibility()
        case .smart:
            if previous.statusHUDMode != .smart
                || previous.statusHUDHideDelay != configuration.statusHUDHideDelay
                || !previous.showHUD
                || !previous.hasCompletedFirstRunSetup {
                noteStatusHUDActivity()
            } else {
                updateHUDVisibility()
            }
        }
    }

    private func noteStatusHUDActivity() {
        guard configuration.showHUD,
              configuration.hasCompletedFirstRunSetup,
              !layerIsActive else { return }

        hudWindowHideTask?.cancel()
        hudWindowHideTask = nil

        switch configuration.statusHUDMode {
        case .hidden:
            concealStatusPill(animated: false)
        case .always:
            stopStatusHUDHideTimer()
            statusHUDPillIsVisible = true
            updateHUDVisibility()
        case .smart:
            statusHUDPillIsVisible = true
            updateHUDVisibility()
            restartStatusHUDHideTimer()
        }
    }

    private func noteBridgeStatusHUDActivity(_ status: BridgeStatus) {
        guard let connectionState = status.statusHUDConnectionState else { return }
        guard lastStatusHUDConnectionState != connectionState else { return }
        lastStatusHUDConnectionState = connectionState
        guard hasStarted else { return }
        noteStatusHUDActivity()
    }

    private func restartStatusHUDHideTimer() {
        stopStatusHUDHideTimer()
        guard configuration.statusHUDMode == .smart else { return }

        let timer = Timer(
            timeInterval: configuration.statusHUDHideDelay.interval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.concealStatusPill(animated: true)
            }
        }
        statusHUDHideTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopStatusHUDHideTimer() {
        statusHUDHideTimer?.invalidate()
        statusHUDHideTimer = nil
    }

    private func concealStatusPill(animated: Bool) {
        stopStatusHUDHideTimer()
        statusHUDPillIsVisible = false
        hudWindowHideTask?.cancel()

        guard animated, !layerIsActive else {
            hudWindowHideTask = nil
            updateHUDVisibility()
            return
        }

        // Keep the transparent panel alive just long enough for SwiftUI's
        // compositor-only fade to finish, then remove it from WindowServer.
        hudWindowHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            self?.hudWindowHideTask = nil
            self?.updateHUDVisibility()
        }
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
        guard let interval = configuration.autoDimTimeout.interval else { return }

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
        guard layerIsActive, pressedControls.isEmpty else {
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
        #if DEBUG
        if let previewValue = ProcessInfo.processInfo.environment[
            "KEYSWITCH_PREVIEW_AUTO_EXIT_SECONDS"
        ], let previewInterval = TimeInterval(previewValue), previewInterval > 0 {
            return previewInterval
        }
        #endif
        return configuration.layerAutoExitTimeout.interval
    }

    private func stopLayerAutoExitTimer() {
        layerAutoExitTimer?.invalidate()
        layerAutoExitTimer = nil
    }

    private func refreshPermissionState(retryIfGranted: Bool) {
        let snapshot = PermissionService.snapshot()
        permissions = snapshot

        if retryIfGranted, snapshot.allGranted, !eventTapIsActive {
            eventTapIsActive = keyboardEngine.start()
        }

        if snapshot.allGranted, eventTapIsActive {
            stopPermissionRefreshTimer()
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
