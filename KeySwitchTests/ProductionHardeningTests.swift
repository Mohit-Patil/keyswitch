import XCTest
@testable import KeySwitch

final class ProductionHardeningTests: XCTestCase {
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
