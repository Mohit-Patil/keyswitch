#!/usr/bin/env swift

import AppKit
import Foundation

private struct IconOutput {
    let pixels: Int
    let filename: String
}

private let scriptURL = URL(fileURLWithPath: #filePath)
private let repositoryRoot = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
private let detailedSourceURL = repositoryRoot
    .appendingPathComponent("docs/brand/keyswitch-logo.svg")
private let compactSourceURL = repositoryRoot
    .appendingPathComponent("docs/brand/keyswitch-mark.svg")
private let appIconDirectory = repositoryRoot
    .appendingPathComponent("KeySwitchApp/Assets.xcassets/AppIcon.appiconset")

private let outputs = [
    IconOutput(pixels: 16, filename: "AppIcon-16.png"),
    IconOutput(pixels: 32, filename: "AppIcon-16@2x.png"),
    IconOutput(pixels: 32, filename: "AppIcon-32.png"),
    IconOutput(pixels: 64, filename: "AppIcon-32@2x.png"),
    IconOutput(pixels: 128, filename: "AppIcon-128.png"),
    IconOutput(pixels: 256, filename: "AppIcon-128@2x.png"),
    IconOutput(pixels: 256, filename: "AppIcon-256.png"),
    IconOutput(pixels: 512, filename: "AppIcon-256@2x.png"),
    IconOutput(pixels: 512, filename: "AppIcon-512.png"),
    IconOutput(pixels: 1024, filename: "AppIcon-512@2x.png")
]

guard let detailedSourceImage = NSImage(contentsOf: detailedSourceURL) else {
    fputs("Unable to load vector master at \(detailedSourceURL.path)\n", stderr)
    exit(1)
}

guard let compactSourceImage = NSImage(contentsOf: compactSourceURL) else {
    fputs("Unable to load compact vector master at \(compactSourceURL.path)\n", stderr)
    exit(1)
}

func renderPNG(sourceImage: NSImage, pixels: Int, destination: URL) throws {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "KeySwitchIconGenerator", code: 1)
    }

    representation.size = NSSize(width: pixels, height: pixels)
    guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
        throw NSError(domain: "KeySwitchIconGenerator", code: 2)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    sourceImage.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "KeySwitchIconGenerator", code: 3)
    }
    try png.write(to: destination, options: .atomic)
}

try FileManager.default.createDirectory(
    at: appIconDirectory,
    withIntermediateDirectories: true
)

for output in outputs {
    let destination = appIconDirectory.appendingPathComponent(output.filename)
    // Small icons need fewer shadows and stronger edges than the full-size
    // artwork. Select the compact master instead of merely downsampling.
    let sourceImage = output.pixels <= 64 ? compactSourceImage : detailedSourceImage
    try renderPNG(sourceImage: sourceImage, pixels: output.pixels, destination: destination)
    print("Generated \(output.filename) (\(output.pixels) px)")
}
