import XCTest
@testable import KeySwitch

final class ProductionHardeningTests: XCTestCase {
    func testActivationShortcutAllowsOneOrMoreModifiers() {
        for modifier in ActivationModifier.allCases {
            XCTAssertTrue(
                ActivationShortcut(modifiers: [modifier]).isValid,
                "Expected \(modifier.title) to work as a single-modifier shortcut"
            )
        }

        XCTAssertTrue(ActivationShortcut.standard.isValid)
        XCTAssertFalse(ActivationShortcut(modifiers: []).isValid)
    }

    func testPermissionSetupRequiresOnlyAccessibility() {
        XCTAssertEqual(KeyboardPermissionKind.allCases, [.accessibility])
        XCTAssertEqual(
            PermissionService.nextRequiredPermission(
                in: PermissionSnapshot(
                    accessibilityGranted: false
                )
            ),
            .accessibility
        )
        XCTAssertNil(
            PermissionService.nextRequiredPermission(
                in: PermissionSnapshot(
                    accessibilityGranted: true
                )
            )
        )
    }

    func testKeyboardReadinessRequiresCurrentGrantAndActiveTap() {
        XCTAssertFalse(
            PermissionSnapshot(accessibilityGranted: false)
                .keyboardAccessIsReady(eventTapIsActive: true),
            "A lingering event tap must not mask a revoked Accessibility grant"
        )
        XCTAssertFalse(
            PermissionSnapshot(accessibilityGranted: true)
                .keyboardAccessIsReady(eventTapIsActive: false)
        )
        XCTAssertTrue(
            PermissionSnapshot(accessibilityGranted: true)
                .keyboardAccessIsReady(eventTapIsActive: true)
        )
    }

    func testLiveEventTapProbeOverridesStaleAccessibilityCache() {
        XCTAssertTrue(
            PermissionService.resolveAccessibilityGrant(
                cachedAPIValue: false,
                eventTapProbeSucceeded: true
            ),
            "A live tap must recognize a grant even when AXIsProcessTrusted is stale false"
        )
        XCTAssertFalse(
            PermissionService.resolveAccessibilityGrant(
                cachedAPIValue: true,
                eventTapProbeSucceeded: false
            ),
            "A failed live tap must recognize revocation even when AXIsProcessTrusted is stale true"
        )
    }

    func testCodexSetupRelaunchReturnsToKeySwitchBeforeFinalMicroStep() {
        XCTAssertFalse(CodexSetupRelaunchPolicy.activatesCodexOnLaunch)
        XCTAssertEqual(
            CodexSetupRelaunchPolicy.reconnectTimeoutNanoseconds,
            20_000_000_000
        )
        XCTAssertEqual(
            CodexSetupRelaunchPolicy.reconnectAction(openMicroOnboarding: false),
            .showKeySwitch
        )
        XCTAssertEqual(
            CodexSetupRelaunchPolicy.reconnectAction(openMicroOnboarding: true),
            .openMicroOnboarding
        )
    }

    func testCodexProtocolResponseParserAcceptsRuntimeValues() throws {
        let result = CodexProtocolResponseParser.result(
            from: [
                "result": [
                    "result": ["type": "boolean", "value": true],
                ],
            ]
        )

        guard case .success(let value) = result else {
            return XCTFail("Expected a successful protocol response")
        }
        XCTAssertEqual(value as? Bool, true)
    }

    func testCodexProtocolResponseParserSurfacesProtocolErrors() {
        let result = CodexProtocolResponseParser.result(
            from: ["error": ["message": "Renderer unavailable"]]
        )

        guard case .failure(let error) = result else {
            return XCTFail("Expected a protocol failure")
        }
        XCTAssertEqual(error, .protocolError("Renderer unavailable"))
    }

    func testCodexProtocolResponseParserSurfacesJavaScriptExceptions() {
        let result = CodexProtocolResponseParser.result(
            from: [
                "result": [
                    "result": ["type": "object"],
                    "exceptionDetails": [
                        "text": "Uncaught",
                        "exception": ["description": "Micro setup changed"],
                    ],
                ],
            ]
        )

        guard case .failure(let error) = result else {
            return XCTFail("Expected a runtime failure")
        }
        XCTAssertEqual(error, .runtimeException("Micro setup changed"))
    }

    func testPermissionSettingsAnchorsMatchMacOSPrivacyPanes() {
        XCTAssertEqual(
            KeyboardPermissionKind.accessibility.settingsAnchor,
            "Privacy_Accessibility"
        )
    }

    func testPermissionGuideConvertsQuartzCoordinatesAcrossDisplays() {
        let frame = PermissionGuideGeometry.cocoaFrame(
            quartzFrame: CGRect(x: -1440, y: -200, width: 900, height: 700),
            mainScreenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117)
        )

        XCTAssertEqual(frame, CGRect(x: -1440, y: 617, width: 900, height: 700))
    }

    func testPermissionGuidePanelIsClampedToItsVisibleDisplay() {
        let visibleFrame = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let frame = PermissionGuideGeometry.clampedPanelFrame(
            settingsFrame: CGRect(x: -1500, y: -40, width: 1100, height: 760),
            visibleScreenFrame: visibleFrame,
            contentHeight: 96
        )

        XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX + 12)
        XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX - 12)
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY + 12)
        XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY - 12)
    }

    func testLayerAutoExitOnlyAppliesToToggleMode() {
        var configuration = AppConfiguration.default
        configuration.layerAutoExitTimeout = .fiveSeconds

        configuration.activationMode = .hold
        XCTAssertNil(configuration.layerAutoExitInterval)

        configuration.activationMode = .toggle
        XCTAssertEqual(configuration.layerAutoExitInterval, 5)

        configuration.layerAutoExitTimeout = .never
        XCTAssertNil(configuration.layerAutoExitInterval)
    }

    func testVisualAndLifecyclePreferencesDoNotChangeKeyboardEngineSignature() {
        let baseline = AppConfiguration.default
        let baselineSignature = KeyboardEngineConfigurationSignature(configuration: baseline)

        var updated = baseline
        updated.layerAutoExitTimeout = .fiveSeconds
        updated.showHUD.toggle()
        updated.hudAppearance = .dark
        updated.expandedHUDSize = .extraLarge
        updated.showMenuBarAgentStatus.toggle()
        updated.menuBarIndicatorSize = .large
        updated.lightingBrightness = 0.5
        updated.animatedAgentLighting.toggle()
        updated.autoDimTimeout = .never
        updated.focusCodexOnSingleTap.toggle()
        updated.hasCompletedFirstRunSetup.toggle()
        updated.debugPort += 1

        XCTAssertEqual(
            KeyboardEngineConfigurationSignature(configuration: updated),
            baselineSignature
        )
    }

    func testEveryKeyboardInputPreferenceChangesKeyboardEngineSignature() {
        let baseline = AppConfiguration.default
        let baselineSignature = KeyboardEngineConfigurationSignature(configuration: baseline)

        var activationMode = baseline
        activationMode.activationMode = .toggle
        XCTAssertNotEqual(
            KeyboardEngineConfigurationSignature(configuration: activationMode),
            baselineSignature
        )

        var activationShortcut = baseline
        activationShortcut.activationShortcut = ActivationShortcut(modifiers: [.option, .command])
        XCTAssertNotEqual(
            KeyboardEngineConfigurationSignature(configuration: activationShortcut),
            baselineSignature
        )

        var blocking = baseline
        blocking.blockUnmappedKeys.toggle()
        XCTAssertNotEqual(
            KeyboardEngineConfigurationSignature(configuration: blocking),
            baselineSignature
        )

        var bindings = baseline
        bindings.bindings[0].physicalKey = nil
        XCTAssertNotEqual(
            KeyboardEngineConfigurationSignature(configuration: bindings),
            baselineSignature
        )
    }

    func testAgentStatusesUseAConsistentColorOnlyCircularMenuBarSilhouette() {
        XCTAssertEqual(
            MenuBarStatusIconRenderer.indicatorSymbol(for: .off),
            .hollowCircle
        )

        let activeStatuses = AgentLightStatus.allCases.filter { $0 != .off }
        XCTAssertTrue(activeStatuses.allSatisfy {
            MenuBarStatusIconRenderer.indicatorSymbol(for: $0) == .circle
        })
    }
}
