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
            .unavailable
        )
    }

    func testOnlyRegisteredStatesKeepTheToggleEnabled() {
        XCTAssertFalse(LaunchAtLoginState.disabled.isRequested)
        XCTAssertTrue(LaunchAtLoginState.enabled.isRequested)
        XCTAssertTrue(LaunchAtLoginState.requiresApproval.isRequested)
        XCTAssertFalse(LaunchAtLoginState.unavailable.isRequested)
    }
}
