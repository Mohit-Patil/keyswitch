import AppKit
import SwiftUI

struct MenuBarStatusLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let model: AppModel

    private var accessibilityValue: String {
        let assignedAgents = (0..<6).compactMap { slot -> String? in
            let light = model.lightingSnapshot.light(for: slot)
            guard light.status != .off else { return nil }
            let selection = light.selected ? ", selected" : ""
            return "Agent \(slot + 1): \(light.status.title)\(selection)"
        }

        let agentSummary = assignedAgents.isEmpty
            ? "No assigned agents"
            : assignedAgents.joined(separator: ", ")
        return "\(model.bridgeStatus.title). \(agentSummary)"
    }

    var body: some View {
        Image(
            nsImage: MenuBarStatusIconRenderer.image(
                layerIsActive: model.layerIsActive,
                showsAgentStatus: model.configuration.showMenuBarAgentStatus,
                indicatorSize: model.configuration.menuBarIndicatorSize,
                lights: (0..<6).map(model.lightingSnapshot.light(for:)),
                colorScheme: colorScheme
            )
        )
        .renderingMode(.original)
        .contentTransition(.interpolate)
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.18),
            value: model.lightingSnapshot
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.18),
            value: model.configuration.menuBarIndicatorSize
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.layerIsActive ? "KeySwitch layer active" : "KeySwitch")
        .accessibilityValue(accessibilityValue)
    }
}

enum MenuBarStatusIndicatorSymbol: Equatable {
    case hollowCircle
    case circle
}

enum MenuBarStatusIconRenderer {
    private static let imageHeight: CGFloat = 16
    private static let keyboardWidth: CGFloat = 14

    static func image(
        layerIsActive: Bool,
        showsAgentStatus: Bool,
        indicatorSize: MenuBarIndicatorSize,
        lights: [AgentLightState],
        colorScheme: ColorScheme
    ) -> NSImage {
        let metrics = MenuBarStatusIndicatorMetrics(size: indicatorSize)
        let width = showsAgentStatus ? metrics.imageWidth : keyboardWidth
        let image = NSImage(size: NSSize(width: width, height: imageHeight), flipped: false) { rect in
            drawKeyboard(
                layerIsActive: layerIsActive,
                colorScheme: colorScheme,
                in: rect
            )

            if showsAgentStatus {
                drawIndicators(
                    lights,
                    colorScheme: colorScheme,
                    metrics: metrics,
                    in: rect
                )
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawKeyboard(
        layerIsActive: Bool,
        colorScheme: ColorScheme,
        in rect: NSRect
    ) {
        let foreground = colorScheme == .dark ? NSColor.white : NSColor.black
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [foreground]))
        guard let symbol = NSImage(
            systemSymbolName: layerIsActive ? "keyboard.fill" : "keyboard",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(symbolConfiguration) else { return }

        let symbolSize = symbol.size
        let scale = min(keyboardWidth / symbolSize.width, 12 / symbolSize.height)
        let drawSize = NSSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
        symbol.draw(
            in: NSRect(
                x: (keyboardWidth - drawSize.width) / 2,
                y: (rect.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }

    private static func drawIndicators(
        _ lights: [AgentLightState],
        colorScheme: ColorScheme,
        metrics: MenuBarStatusIndicatorMetrics,
        in rect: NSRect
    ) {
        for slot in 0..<6 {
            let state = lights.first(where: { $0.id == slot }) ?? AgentLightState.offSlots[slot]
            let color = indicatorColor(for: state.status, colorScheme: colorScheme)
            let cellRect = metrics.cellRect(for: slot, in: rect)
            let center = NSPoint(
                x: cellRect.midX,
                y: cellRect.midY
            )

            // A status must never paint into its neighbour. This is especially
            // noticeable for the high-luminance Complete green on Retina menu
            // bars, where even a sub-point overlap reads as a merged light.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: cellRect).addClip()

            // The menu bar is a compact status surface. Selection remains in
            // the accessibility value and the full HUD, but it must not alter
            // a light's silhouette here: a ring reads as a separate hollow
            // icon beside the other filled dots at menu-bar scale.
            let diameter = metrics.dotDiameter
            let dotRect = NSRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            drawIndicator(
                symbol: indicatorSymbol(for: state.status),
                color: color,
                metrics: metrics,
                in: dotRect
            )
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    static func indicatorSymbol(
        for status: AgentLightStatus
    ) -> MenuBarStatusIndicatorSymbol {
        switch status {
        case .off: .hollowCircle
        case .idle, .working, .unread, .awaitingApproval, .awaitingResponse, .error: .circle
        }
    }

    private static func drawIndicator(
        symbol: MenuBarStatusIndicatorSymbol,
        color: NSColor,
        metrics: MenuBarStatusIndicatorMetrics,
        in rect: NSRect
    ) {
        if symbol == .hollowCircle {
            color.setStroke()
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.2, dy: 0.2))
            path.lineWidth = max(metrics.outlineLineWidth, 0.65)
            path.stroke()
            return
        }

        let path = indicatorPath(for: symbol, in: rect)
        color.setFill()
        path.fill()

        NSColor.black.withAlphaComponent(0.42).setStroke()
        path.lineWidth = metrics.outlineLineWidth
        path.stroke()
    }

    private static func indicatorPath(
        for symbol: MenuBarStatusIndicatorSymbol,
        in rect: NSRect
    ) -> NSBezierPath {
        switch symbol {
        case .hollowCircle, .circle:
            return NSBezierPath(ovalIn: rect)
        }
    }

    private static func indicatorColor(
        for status: AgentLightStatus,
        colorScheme: ColorScheme
    ) -> NSColor {
        guard status != .off else {
            let foreground = colorScheme == .dark ? NSColor.white : NSColor.black
            return foreground.withAlphaComponent(0.32)
        }

        let rgb = status.packedRGB
        return NSColor(
            deviceRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct MenuBarStatusIndicatorMetrics {
    let imageWidth: CGFloat
    let startX: CGFloat
    let cellWidth: CGFloat
    let dotDiameter: CGFloat
    let outlineLineWidth: CGFloat

    var maximumPaintDiameter: CGFloat {
        dotDiameter + outlineLineWidth
    }

    func cellRect(for slot: Int, in imageRect: NSRect) -> NSRect {
        NSRect(
            x: imageRect.minX + startX + CGFloat(slot) * cellWidth,
            y: imageRect.minY,
            width: cellWidth,
            height: imageRect.height
        )
    }

    init(size: MenuBarIndicatorSize) {
        switch size {
        case .compact:
            imageWidth = 48
            startX = 18
            cellWidth = 5
            dotDiameter = 3.75
            outlineLineWidth = 0.4
        case .standard:
            imageWidth = 57
            startX = 17.5
            cellWidth = 6.5
            dotDiameter = 5
            outlineLineWidth = 0.45
        case .large:
            imageWidth = 65
            startX = 17.5
            cellWidth = 7.75
            dotDiameter = 6.25
            outlineLineWidth = 0.5
        case .extraLarge:
            imageWidth = 73
            startX = 17.5
            cellWidth = 9
            dotDiameter = 7.5
            outlineLineWidth = 0.55
        }
    }
}
