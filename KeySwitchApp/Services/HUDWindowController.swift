import AppKit
import SwiftUI

@MainActor
final class HUDWindowController {
    private unowned let model: AppModel
    private var panel: NSPanel?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let panel = panel ?? makePanel()
        guard !panel.isVisible else { return }
        applyAppearance(to: panel)
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func updateAppearance() {
        guard let panel else { return }
        applyAppearance(to: panel)
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 384, height: 384)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient,
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        applyAppearance(to: panel)
        // The frosted chassis already supplies its own rounded edge treatment.
        // A WindowServer shadow follows the rectangular NSPanel frame and can
        // appear as a second window around the transparent corners.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: MicroHUDOverlayView(model: model))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView
        self.panel = panel
        return panel
    }

    private func applyAppearance(to panel: NSPanel) {
        switch model.effectiveHUDAppearance {
        case .system:
            panel.appearance = nil
        case .light:
            panel.appearance = NSAppearance(named: .aqua)
        case .dark:
            panel.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let horizontalMargin: CGFloat = 16
        let topMargin: CGFloat = 12
        let origin = NSPoint(
            x: visibleFrame.maxX - panel.frame.width - horizontalMargin,
            y: visibleFrame.maxY - panel.frame.height - topMargin
        )
        panel.setFrameOrigin(origin)
    }
}
