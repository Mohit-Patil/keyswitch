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
    case diamond
    case square
    case triangleUp
    case triangleDown
    case error
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
        let metrics = IndicatorMetrics(size: indicatorSize)
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
        metrics: IndicatorMetrics,
        in rect: NSRect
    ) {
        for slot in 0..<6 {
            let state = lights.first(where: { $0.id == slot }) ?? AgentLightState.offSlots[slot]
            let color = indicatorColor(for: state.status, colorScheme: colorScheme)
            let center = NSPoint(
                x: metrics.startX + CGFloat(slot) * metrics.cellWidth + metrics.cellWidth / 2,
                y: rect.midY
            )

            if state.selected, state.status != .off {
                color.withAlphaComponent(0.72).setStroke()
                let ringRect = NSRect(
                    x: center.x - metrics.ringDiameter / 2,
                    y: center.y - metrics.ringDiameter / 2,
                    width: metrics.ringDiameter,
                    height: metrics.ringDiameter
                )
                let ring = NSBezierPath(ovalIn: ringRect)
                ring.lineWidth = metrics.ringLineWidth
                ring.stroke()
            }

            let diameter = state.selected && state.status != .off
                ? metrics.selectedDotDiameter
                : metrics.dotDiameter
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
        }
    }

    static func indicatorSymbol(
        for status: AgentLightStatus
    ) -> MenuBarStatusIndicatorSymbol {
        switch status {
        case .off: .hollowCircle
        case .idle: .circle
        case .working: .diamond
        case .unread: .square
        case .awaitingApproval: .triangleUp
        case .awaitingResponse: .triangleDown
        case .error: .error
        }
    }

    private static func drawIndicator(
        symbol: MenuBarStatusIndicatorSymbol,
        color: NSColor,
        metrics: IndicatorMetrics,
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

        NSColor.black.withAlphaComponent(symbol == .circle ? 0.42 : 0.24).setStroke()
        path.lineWidth = metrics.outlineLineWidth
        path.stroke()

        guard symbol == .error else { return }
        NSColor.white.withAlphaComponent(0.92).setStroke()
        let inset = max(1, rect.width * 0.27)
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: rect.minX + inset, y: rect.minY + inset))
        cross.line(to: NSPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        cross.move(to: NSPoint(x: rect.minX + inset, y: rect.maxY - inset))
        cross.line(to: NSPoint(x: rect.maxX - inset, y: rect.minY + inset))
        cross.lineWidth = max(metrics.outlineLineWidth, 0.65)
        cross.lineCapStyle = .round
        cross.stroke()
    }

    private static func indicatorPath(
        for symbol: MenuBarStatusIndicatorSymbol,
        in rect: NSRect
    ) -> NSBezierPath {
        switch symbol {
        case .hollowCircle, .circle, .error:
            return NSBezierPath(ovalIn: rect)
        case .diamond:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.midX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
            path.line(to: NSPoint(x: rect.midX, y: rect.minY))
            path.line(to: NSPoint(x: rect.minX, y: rect.midY))
            path.close()
            return path
        case .square:
            return NSBezierPath(
                roundedRect: rect,
                xRadius: max(0.7, rect.width * 0.18),
                yRadius: max(0.7, rect.height * 0.18)
            )
        case .triangleUp, .triangleDown:
            let points: [NSPoint]
            if symbol == .triangleUp {
                points = [
                    NSPoint(x: rect.midX, y: rect.maxY),
                    NSPoint(x: rect.maxX, y: rect.minY),
                    NSPoint(x: rect.minX, y: rect.minY),
                ]
            } else {
                points = [
                    NSPoint(x: rect.minX, y: rect.maxY),
                    NSPoint(x: rect.maxX, y: rect.maxY),
                    NSPoint(x: rect.midX, y: rect.minY),
                ]
            }
            let path = NSBezierPath()
            path.move(to: points[0])
            path.line(to: points[1])
            path.line(to: points[2])
            path.close()
            return path
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

private struct IndicatorMetrics {
    let imageWidth: CGFloat
    let startX: CGFloat
    let cellWidth: CGFloat
    let dotDiameter: CGFloat
    let selectedDotDiameter: CGFloat
    let ringDiameter: CGFloat
    let ringLineWidth: CGFloat
    let outlineLineWidth: CGFloat

    init(size: MenuBarIndicatorSize) {
        switch size {
        case .compact:
            imageWidth = 47
            startX = 18
            cellWidth = 5
            dotDiameter = 3.75
            selectedDotDiameter = 4.5
            ringDiameter = 5.5
            ringLineWidth = 0.65
            outlineLineWidth = 0.4
        case .standard:
            imageWidth = 57
            startX = 17.5
            cellWidth = 6.5
            dotDiameter = 5
            selectedDotDiameter = 5.75
            ringDiameter = 7
            ringLineWidth = 0.75
            outlineLineWidth = 0.45
        case .large:
            imageWidth = 65
            startX = 17.5
            cellWidth = 7.75
            dotDiameter = 6.25
            selectedDotDiameter = 7
            ringDiameter = 8.5
            ringLineWidth = 0.85
            outlineLineWidth = 0.5
        case .extraLarge:
            imageWidth = 73
            startX = 17.5
            cellWidth = 9
            dotDiameter = 7.5
            selectedDotDiameter = 8.25
            ringDiameter = 10
            ringLineWidth = 1
            outlineLineWidth = 0.55
        }
    }
}
