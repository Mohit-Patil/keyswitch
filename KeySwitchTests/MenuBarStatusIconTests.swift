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

    func testSelectionDoesNotChangeMenuBarIndicatorPixels() throws {
        for size in MenuBarIndicatorSize.allCases {
            for status in AgentLightStatus.allCases {
                var unselectedLights = AgentLightState.offSlots
                unselectedLights[0] = AgentLightState(
                    id: 0,
                    title: "Test agent",
                    threadKey: "test:0",
                    status: status,
                    selected: false
                )

                var selectedLights = unselectedLights
                selectedLights[0] = AgentLightState(
                    id: 0,
                    title: "Test agent",
                    threadKey: "test:0",
                    status: status,
                    selected: true
                )

                let unselectedImage = MenuBarStatusIconRenderer.image(
                    layerIsActive: false,
                    showsAgentStatus: true,
                    indicatorSize: size,
                    lights: unselectedLights,
                    colorScheme: .dark
                )
                let selectedImage = MenuBarStatusIconRenderer.image(
                    layerIsActive: false,
                    showsAgentStatus: true,
                    indicatorSize: size,
                    lights: selectedLights,
                    colorScheme: .dark
                )

                XCTAssertEqual(
                    try pngData(of: selectedImage),
                    try pngData(of: unselectedImage),
                    "Selection changed the \(size.title) \(status.title) indicator"
                )
            }
        }
    }

    func testEveryActiveIndicatorInteriorContainsOnlyItsStatusColor() throws {
        let scale = 8
        let activeStatuses = AgentLightStatus.allCases.filter { $0 != .off }

        for colorScheme in [ColorScheme.light, .dark] {
            for size in MenuBarIndicatorSize.allCases {
                let metrics = MenuBarStatusIndicatorMetrics(size: size)
                let imageRect = NSRect(x: 0, y: 0, width: metrics.imageWidth, height: 16)
                let cell = metrics.cellRect(for: 0, in: imageRect)
                let sampleOffset = metrics.dotDiameter * 0.14

                for status in activeStatuses {
                    var lights = AgentLightState.offSlots
                    lights[0] = AgentLightState(
                        id: 0,
                        title: status.title,
                        threadKey: "test:0",
                        status: status,
                        selected: true
                    )

                    let image = MenuBarStatusIconRenderer.image(
                        layerIsActive: false,
                        showsAgentStatus: true,
                        indicatorSize: size,
                        lights: lights,
                        colorScheme: colorScheme
                    )
                    let bitmap = try bitmapRepresentation(of: image, scale: scale)
                    let rgb = status.packedRGB
                    let expectedRed = CGFloat((rgb >> 16) & 0xFF) / 255
                    let expectedGreen = CGFloat((rgb >> 8) & 0xFF) / 255
                    let expectedBlue = CGFloat(rgb & 0xFF) / 255

                    for xOffset in [-sampleOffset, 0, sampleOffset] {
                        for yOffset in [-sampleOffset, 0, sampleOffset] {
                            let x = Int((cell.midX + xOffset) * CGFloat(scale))
                            let y = Int((imageRect.midY + yOffset) * CGFloat(scale))
                            let color = try XCTUnwrap(
                                bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                            )

                            XCTAssertEqual(color.redComponent, expectedRed, accuracy: 0.04)
                            XCTAssertEqual(color.greenComponent, expectedGreen, accuracy: 0.04)
                            XCTAssertEqual(color.blueComponent, expectedBlue, accuracy: 0.04)
                            XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.02)
                        }
                    }
                }
            }
        }
    }

    func testUnassignedIndicatorRemainsHollowAtEverySizeAndAppearance() throws {
        let scale = 8

        for colorScheme in [ColorScheme.light, .dark] {
            for size in MenuBarIndicatorSize.allCases {
                let image = MenuBarStatusIconRenderer.image(
                    layerIsActive: false,
                    showsAgentStatus: true,
                    indicatorSize: size,
                    lights: AgentLightState.offSlots,
                    colorScheme: colorScheme
                )
                let bitmap = try bitmapRepresentation(of: image, scale: scale)
                let metrics = MenuBarStatusIndicatorMetrics(size: size)
                let cell = metrics.cellRect(
                    for: 0,
                    in: NSRect(origin: .zero, size: image.size)
                )
                let center = try XCTUnwrap(
                    bitmap.colorAt(
                        x: Int(cell.midX * CGFloat(scale)),
                        y: Int(image.size.height / 2 * CGFloat(scale))
                    )?.usingColorSpace(.deviceRGB)
                )

                XCTAssertLessThan(center.alphaComponent, 0.02)
            }
        }
    }

    func testEveryActiveStatusNeverBleedsIntoAnotherSlot() throws {
        let scale = 2
        let activeStatuses = AgentLightStatus.allCases.filter { $0 != .off }

        for colorScheme in [ColorScheme.light, .dark] {
            for size in MenuBarIndicatorSize.allCases {
                let baselineImage = MenuBarStatusIconRenderer.image(
                    layerIsActive: false,
                    showsAgentStatus: true,
                    indicatorSize: size,
                    lights: AgentLightState.offSlots,
                    colorScheme: colorScheme
                )
                let baseline = try bitmapRepresentation(of: baselineImage, scale: scale)
                let metrics = MenuBarStatusIndicatorMetrics(size: size)

                for status in activeStatuses {
                    for selectedSlot in 0..<6 {
                        var lights = AgentLightState.offSlots
                        lights[selectedSlot] = AgentLightState(
                            id: selectedSlot,
                            title: status.title,
                            threadKey: "test:\(selectedSlot)",
                            status: status,
                            selected: true
                        )

                        let image = MenuBarStatusIconRenderer.image(
                            layerIsActive: false,
                            showsAgentStatus: true,
                            indicatorSize: size,
                            lights: lights,
                            colorScheme: colorScheme
                        )
                        let bitmap = try bitmapRepresentation(of: image, scale: scale)
                        let slotRect = metrics.cellRect(
                            for: selectedSlot,
                            in: NSRect(origin: .zero, size: image.size)
                        )

                        for y in 0..<bitmap.pixelsHigh {
                            for x in 0..<bitmap.pixelsWide {
                                let logicalX = (CGFloat(x) + 0.5) / CGFloat(scale)
                                guard logicalX < slotRect.minX || logicalX > slotRect.maxX else {
                                    continue
                                }

                                let actual = try XCTUnwrap(
                                    bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                                )
                                let expected = try XCTUnwrap(
                                    baseline.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                                )
                                let maximumDelta = [
                                    abs(actual.redComponent - expected.redComponent),
                                    abs(actual.greenComponent - expected.greenComponent),
                                    abs(actual.blueComponent - expected.blueComponent),
                                    abs(actual.alphaComponent - expected.alphaComponent),
                                ].max() ?? 0

                                XCTAssertLessThanOrEqual(
                                    maximumDelta,
                                    0.01,
                                    "\(size.title) \(status.title) escaped slot \(selectedSlot + 1) at x=\(logicalX)"
                                )
                            }
                        }
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

    private func pngData(of image: NSImage) throws -> Data {
        let bitmap = try bitmapRepresentation(of: image, scale: 4)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
