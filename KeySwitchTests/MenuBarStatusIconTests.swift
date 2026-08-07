import AppKit
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

        XCTAssertEqual(widths, [48, 57, 65, 73])
    }

    func testEveryIndicatorPaintFootprintFitsInsideItsSlotAndCanvas() {
        for size in MenuBarIndicatorSize.allCases {
            let metrics = MenuBarStatusIndicatorMetrics(size: size)
            let imageRect = NSRect(x: 0, y: 0, width: metrics.imageWidth, height: 16)

            XCTAssertLessThan(
                metrics.maximumPaintDiameter,
                metrics.cellWidth,
                "\(size.title) indicator paint must leave space between slots"
            )

            for slot in 0..<6 {
                let cell = metrics.cellRect(for: slot, in: imageRect)
                XCTAssertGreaterThanOrEqual(cell.minX, imageRect.minX)
                XCTAssertLessThanOrEqual(cell.maxX, imageRect.maxX)
            }
        }
    }

    func testSelectedCompleteGreenNeverBleedsIntoAnotherSlot() throws {
        let scale = 4

        for size in MenuBarIndicatorSize.allCases {
            for selectedSlot in 0..<6 {
                var lights = AgentLightState.offSlots
                lights[selectedSlot] = AgentLightState(
                    id: selectedSlot,
                    title: "Complete",
                    threadKey: "test:\(selectedSlot)",
                    status: .unread,
                    selected: true
                )

                let image = MenuBarStatusIconRenderer.image(
                    layerIsActive: false,
                    showsAgentStatus: true,
                    indicatorSize: size,
                    lights: lights,
                    colorScheme: .dark
                )
                let bitmap = try bitmapRepresentation(of: image, scale: scale)
                let metrics = MenuBarStatusIndicatorMetrics(size: size)
                let slotRect = metrics.cellRect(
                    for: selectedSlot,
                    in: NSRect(origin: .zero, size: image.size)
                )

                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                              color.alphaComponent > 0.02,
                              color.greenComponent > 0.45,
                              color.greenComponent > color.redComponent + 0.2,
                              color.greenComponent > color.blueComponent + 0.1 else {
                            continue
                        }

                        let logicalX = (CGFloat(x) + 0.5) / CGFloat(scale)
                        XCTAssertTrue(
                            slotRect.contains(NSPoint(x: logicalX, y: slotRect.midY)),
                            "\(size.title) Complete green escaped slot \(selectedSlot + 1) at x=\(logicalX)"
                        )
                    }
                }
            }
        }
    }

    private func bitmapRepresentation(
        of image: NSImage,
        scale: Int
    ) throws -> NSBitmapImageRep {
        let pixelsWide = Int(image.size.width * CGFloat(scale))
        let pixelsHigh = Int(image.size.height * CGFloat(scale))
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelsWide,
                pixelsHigh: pixelsHigh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: [],
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        bitmap.size = image.size

        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        return bitmap
    }
}
