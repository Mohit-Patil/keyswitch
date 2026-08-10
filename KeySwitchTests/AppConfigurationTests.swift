import Foundation
import XCTest
@testable import KeySwitch

final class AppConfigurationTests: XCTestCase {
    func testDebugPortValidationAcceptsOnlyTCPPortRange() {
        XCTAssertFalse(AppConfiguration.isValidDebugPort(0))
        XCTAssertTrue(AppConfiguration.isValidDebugPort(1))
        XCTAssertTrue(AppConfiguration.isValidDebugPort(65_535))
        XCTAssertFalse(AppConfiguration.isValidDebugPort(65_536))
    }

    func testInitializerReplacesInvalidDebugPortWithDefault() {
        var configuration = AppConfiguration.default
        configuration = AppConfiguration(
            activationMode: configuration.activationMode,
            activationShortcut: configuration.activationShortcut,
            showHUD: configuration.showHUD,
            blockUnmappedKeys: configuration.blockUnmappedKeys,
            debugPort: 70_000,
            bindings: configuration.bindings
        )

        XCTAssertEqual(configuration.debugPort, AppConfiguration.defaultDebugPort)
    }

    func testMutationPreservesLastValidDebugPort() {
        var configuration = AppConfiguration.default
        configuration.debugPort = 12_345
        configuration.debugPort = 0
        XCTAssertEqual(configuration.debugPort, 12_345)

        configuration.debugPort = 65_536
        XCTAssertEqual(configuration.debugPort, 12_345)
    }

    func testDecodingReplacesOutOfRangeDebugPortWithDefault() throws {
        let data = try configurationData(debugPort: 70_000)
        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(configuration.debugPort, AppConfiguration.defaultDebugPort)
    }

    func testDecodingReplacesMalformedDebugPortWithDefault() throws {
        let data = try configurationData(debugPort: "not-a-port")
        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(configuration.debugPort, AppConfiguration.defaultDebugPort)
    }

    func testValidDebugPortRoundTrips() throws {
        var configuration = AppConfiguration.default
        configuration.debugPort = 12_345

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(decoded.debugPort, 12_345)
    }

    func testSingleModifierActivationShortcutRoundTrips() throws {
        var configuration = AppConfiguration.default
        configuration.activationShortcut = ActivationShortcut(modifiers: [.function])

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(
            decoded.activationShortcut,
            ActivationShortcut(modifiers: [.function])
        )
    }

    func testKeyActivationShortcutsRoundTrip() throws {
        for shortcut in [
            ActivationShortcut(modifiers: [], key: .g),
            ActivationShortcut(modifiers: [.control, .command], key: .g),
        ] {
            var configuration = AppConfiguration.default
            configuration.activationShortcut = shortcut

            let data = try JSONEncoder().encode(configuration)
            let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

            XCTAssertEqual(decoded.activationShortcut, shortcut)
        }
    }

    func testLegacyModifierOnlyActivationShortcutStillDecodes() throws {
        let data = Data(#"{"modifiers":["control"]}"#.utf8)
        let shortcut = try JSONDecoder().decode(ActivationShortcut.self, from: data)

        XCTAssertEqual(shortcut, ActivationShortcut(modifiers: [.control]))
        XCTAssertNil(shortcut.key)
    }

    func testImpossibleModifierTriggerKeyFallsBackToStandardShortcut() throws {
        let encoded = try JSONEncoder().encode(AppConfiguration.default)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["activationShortcut"] = [
            "modifiers": [],
            "key": [
                "keyCode": 54,
                "displayName": "Forged Right Command",
                "isModifier": false,
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(decoded.activationShortcut, .standard)
    }

    private func configurationData(debugPort: Any) throws -> Data {
        let encoded = try JSONEncoder().encode(AppConfiguration.default)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["debugPort"] = debugPort
        return try JSONSerialization.data(withJSONObject: object)
    }
}
