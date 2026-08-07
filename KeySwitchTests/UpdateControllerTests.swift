import XCTest
@testable import KeySwitch

@MainActor
final class UpdateControllerTests: XCTestCase {
    func testPreparedUpdateActionRunsOnFirstInstallRequest() {
        var installationCount = 0
        let action = PreparedUpdateAction {
            installationCount += 1
        }

        let updater = SparkleUpdaterController(
            savedAutomaticUpdates: false,
            currentVersion: "0.2.0 (3)",
            startingUpdater: false
        )
        updater.prepareUpdateForInstallation(version: "0.2.1", action: action)

        updater.installUpdate()

        XCTAssertEqual(installationCount, 1)
        XCTAssertTrue(updater.updateStatus.isUpdateReady)
        XCTAssertEqual(updater.updateStatus.availableVersion, "0.2.1")
    }

    func testPreparedUpdateCanBeInvokedAgainWhenTerminationWasCanceled() {
        var installationCount = 0
        let action = PreparedUpdateAction {
            installationCount += 1
        }

        let updater = SparkleUpdaterController(
            savedAutomaticUpdates: false,
            startingUpdater: false
        )
        updater.prepareUpdateForInstallation(version: "0.2.1", action: action)

        updater.installUpdate()
        updater.installUpdate()

        XCTAssertEqual(installationCount, 2)
    }

    func testClearingPreparedUpdateRemovesRestartState() {
        let updater = SparkleUpdaterController(
            savedAutomaticUpdates: false,
            startingUpdater: false
        )
        updater.prepareUpdateForInstallation(
            version: "0.2.1",
            action: PreparedUpdateAction {}
        )

        updater.clearPreparedUpdate()

        XCTAssertFalse(updater.updateStatus.isUpdateReady)
        XCTAssertNil(updater.updateStatus.availableVersion)
    }

    func testDisabledUpdaterExplainsWhyUpdatesAreUnavailable() {
        let updater = DisabledUpdaterController(
            reason: "Updates are available in official release builds.",
            currentVersion: "0.2.0 (3)"
        )

        XCTAssertFalse(updater.isAvailable)
        XCTAssertFalse(updater.updateStatus.isUpdateReady)
        XCTAssertEqual(updater.currentVersion, "0.2.0 (3)")
        XCTAssertEqual(
            updater.unavailableReason,
            "Updates are available in official release builds."
        )
    }

    func testAutomaticUpdatePreferencePersistsThroughController() throws {
        let suiteName = "UpdateControllerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let updater = SparkleUpdaterController(
            savedAutomaticUpdates: false,
            defaults: defaults,
            startingUpdater: false
        )

        updater.setAutomaticUpdatesEnabled(true)

        XCTAssertTrue(updater.updateStatus.automaticUpdatesEnabled)
        XCTAssertEqual(
            defaults.object(
                forKey: SparkleUpdaterController.automaticUpdatesDefaultsKey
            ) as? Bool,
            true
        )
    }
}
