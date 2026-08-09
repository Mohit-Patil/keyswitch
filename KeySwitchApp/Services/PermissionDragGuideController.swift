import AppKit
import SwiftUI

/// A native file-URL drag source for the installed KeySwitch app bundle.
/// System Settings accepts the same payload as an app dragged from Finder.
private struct AppBundleDragSource: NSViewRepresentable {
    let fileURL: URL
    let onAcceptedDrop: () -> Void

    func makeNSView(context: Context) -> NSView {
        AppBundleDragView(fileURL: fileURL, onAcceptedDrop: onAcceptedDrop)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? AppBundleDragView)?.onAcceptedDrop = onAcceptedDrop
    }
}

private final class AppBundleDragView: NSView, NSDraggingSource {
    private let fileURL: URL
    var onAcceptedDrop: () -> Void

    init(fileURL: URL, onAcceptedDrop: @escaping () -> Void) {
        self.fileURL = fileURL
        self.onAcceptedDrop = onAcceptedDrop
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        let iconSize: CGFloat = 44
        item.setDraggingFrame(
            NSRect(
                x: bounds.midX - iconSize / 2,
                y: bounds.midY - iconSize / 2,
                width: iconSize,
                height: iconSize
            ),
            contents: icon
        )
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        if !operation.isEmpty {
            onAcceptedDrop()
        }
    }
}

/// Returns the visible System Settings window in Cocoa screen coordinates.
/// Window bounds do not require Screen Recording access.
private func systemSettingsWindowFrame() -> CGRect? {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
        as? [[String: Any]] else {
        return nil
    }

    let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
        ?? NSScreen.main?.frame.height
        ?? 900

    for window in windows {
        let ownerName = window[kCGWindowOwnerName as String] as? String
        guard ownerName == "System Settings" || ownerName == "System Preferences" else {
            continue
        }
        guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"],
              let y = bounds["Y"],
              let width = bounds["Width"],
              let height = bounds["Height"],
              width > 300 else {
            continue
        }
        return CGRect(
            x: x,
            y: primaryHeight - y - height,
            width: width,
            height: height
        )
    }

    return nil
}

@MainActor
final class PermissionDragGuideController {
    static let shared = PermissionDragGuideController()

    private let model = PermissionDragGuideModel()
    private var panel: NSPanel?
    private var trackingTimer: Timer?
    private var acceptedDrop = false
    private var settingsSeenAt: Date?

    func present() {
        acceptedDrop = false
        settingsSeenAt = nil
        _ = ensurePanel()
        startTracking()
    }

    func dismiss() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        panel?.orderOut(nil)
        panel?.alphaValue = 0
    }

    private func notifyAcceptedDrop() {
        acceptedDrop = true
        panel?.orderOut(nil)
    }

    private func startTracking() {
        trackingTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePanel()
            }
        }
        trackingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updatePanel() {
        guard let panel else { return }

        if acceptedDrop {
            panel.orderOut(nil)
            return
        }

        let frontmostName = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let settingsIsFrontmost = frontmostName == "System Settings"
            || frontmostName == "System Preferences"
        guard settingsIsFrontmost, systemSettingsWindowFrame() != nil else {
            settingsSeenAt = nil
            panel.orderOut(nil)
            panel.alphaValue = 0
            return
        }

        if settingsSeenAt == nil {
            settingsSeenAt = Date()
        }
        guard panel.isVisible
            || Date().timeIntervalSince(settingsSeenAt ?? .distantFuture) > 0.35 else {
            return
        }

        position(panel)
        guard !panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    private func position(_ panel: NSPanel) {
        guard let settingsFrame = systemSettingsWindowFrame() else { return }

        let sidebarWidth: CGFloat = 215
        let inset: CGFloat = 20
        let width = max(330, settingsFrame.width - sidebarWidth - inset * 2)
        let height = cardHeight(panel, width: width)
        panel.setFrame(
            NSRect(
                x: settingsFrame.minX + sidebarWidth + inset,
                y: settingsFrame.minY + 18,
                width: width,
                height: height
            ),
            display: true
        )
    }

    private func cardHeight(_ panel: NSPanel, width: CGFloat) -> CGFloat {
        if abs(model.cardWidth - width) > 0.5 {
            model.cardWidth = width
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        return max(82, panel.contentView?.fittingSize.height ?? 0)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
            rootView: PermissionDragGuideCard(
                model: model,
                onClose: { [weak self] in self?.dismiss() },
                onAcceptedDrop: { [weak self] in self?.notifyAcceptedDrop() }
            )
        )
        self.panel = panel
        return panel
    }
}

private final class PermissionDragGuideModel: ObservableObject {
    @Published var cardWidth: CGFloat = 360
}

private struct PermissionDragGuideCard: View {
    @ObservedObject var model: PermissionDragGuideModel
    let onClose: () -> Void
    let onAcceptedDrop: () -> Void

    private var appURL: URL { Bundle.main.bundleURL }
    private var appIcon: NSImage { NSWorkspace.shared.icon(forFile: appURL.path) }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.accentColor)

            HStack(spacing: 9) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Drag KeySwitch into the list above")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Then turn its switch on")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .overlay(AppBundleDragSource(fileURL: appURL, onAcceptedDrop: onAcceptedDrop))

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss")
        }
        .padding(12)
        .frame(width: model.cardWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
    }
}
