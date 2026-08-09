import XCTest
@testable import KeySwitch

final class ProductionHardeningTests: XCTestCase {
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

    func testPermissionSettingsAnchorsMatchMacOSPrivacyPanes() {
        XCTAssertEqual(
            KeyboardPermissionKind.accessibility.settingsAnchor,
            "Privacy_Accessibility"
        )
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
