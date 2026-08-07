import SwiftUI
import XCTest
@testable import KeySwitch

final class MenuBarStatusIconTests: XCTestCase {
    func testAgentStatusImageUsesCompactOriginalColorCanvas() {
        let image = MenuBarStatusIconRenderer.image(
            layerIsActive: false,
            showsAgentStatus: true,
            indicatorSize: .standard,
            lights: CodexLightingSnapshot.off.slots,
            colorScheme: .dark
        )

        XCTAssertEqual(image.size.width, 57)
        XCTAssertEqual(image.size.height, 16)
        XCTAssertFalse(image.isTemplate)
    }

    func testKeyboardOnlyImageReclaimsIndicatorWidth() {
        let image = MenuBarStatusIconRenderer.image(
            layerIsActive: true,
            showsAgentStatus: false,
            indicatorSize: .extraLarge,
            lights: CodexLightingSnapshot.off.slots,
            colorScheme: .light
        )

        XCTAssertEqual(image.size.width, 14)
        XCTAssertEqual(image.size.height, 16)
        XCTAssertFalse(image.isTemplate)
    }

    func testIndicatorSizeOptionsUseIncreasingCanvasWidths() {
        let widths = MenuBarIndicatorSize.allCases.map { size in
            MenuBarStatusIconRenderer.image(
                layerIsActive: false,
                showsAgentStatus: true,
                indicatorSize: size,
                lights: CodexLightingSnapshot.off.slots,
                colorScheme: .dark
            ).size.width
        }

        XCTAssertEqual(widths, [47, 57, 65, 73])
    }
}
