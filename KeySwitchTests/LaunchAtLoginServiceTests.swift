import ServiceManagement
import XCTest
@testable import KeySwitch

final class LaunchAtLoginServiceTests: XCTestCase {
    func testServiceStatusesMapToUserFacingStates() {
        XCTAssertEqual(
            LaunchAtLoginService.state(for: .notRegistered),
            .disabled
        )
        XCTAssertEqual(
            LaunchAtLoginService.state(for: .enabled),
            .enabled
        )
        XCTAssertEqual(
            LaunchAtLoginService.state(for: .requiresApproval),
            .requiresApproval
        )
        XCTAssertEqual(
            LaunchAtLoginService.state(for: .notFound),
            .registrationMissing
        )
    }

    func testOnlyRegisteredStatesAppearRequested() {
        XCTAssertFalse(LaunchAtLoginState.disabled.isRequested)
        XCTAssertTrue(LaunchAtLoginState.enabled.isRequested)
        XCTAssertTrue(LaunchAtLoginState.requiresApproval.isRequested)
        XCTAssertFalse(LaunchAtLoginState.registrationMissing.isRequested)
    }

    func testMissingRegistrationExplainsTheRecoveryAction() {
        XCTAssertEqual(
            LaunchAtLoginState.registrationMissing.detail,
            "macOS could not find an existing login-item registration. Keep KeySwitch in Applications, then turn this on to register it again."
        )
    }
}
