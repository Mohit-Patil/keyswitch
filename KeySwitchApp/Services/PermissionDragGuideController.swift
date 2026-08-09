import AppKit
import SwiftUI

/// A native file-URL drag source for the running KeySwitch.app bundle.
/// System Settings accepts this pasteboard payload in its permission lists,
/// just as it accepts an app dragged from Finder.
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
        let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        let iconSize: CGFloat = 44
        draggingItem.setDraggingFrame(
            NSRect(
                x: bounds.midX - iconSize / 2,
                y: bounds.midY - iconSize / 2,
                width: iconSize,
                height: iconSize
            ),
            contents: icon
        )
        beginDraggingSession(with: [draggingItem], event: event, source: self)
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
    private var awaitingGrant = false
    private var settingsSeenAt: Date?

    func present(_ kind: KeyboardPermissionKind) {
        model.kind = kind
        awaitingGrant = false
        settingsSeenAt = nil
        _ = ensurePanel()
        startTracking(kind)
    }

    func dismiss() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        panel?.orderOut(nil)
        panel?.alphaValue = 0
    }

    private func notifyAcceptedDrop() {
        awaitingGrant = true
        panel?.orderOut(nil)
    }

    private func startTracking(_ kind: KeyboardPermissionKind) {
        trackingTimer?.invalidate()
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePanel(for: kind)
            }
        }
        trackingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updatePanel(for kind: KeyboardPermissionKind) {
        guard let panel else { return }

        if kind.isGranted(in: PermissionService.snapshot()) {
            dismiss()
            return
        }

        if awaitingGrant {
            if panel.isVisible {
                panel.orderOut(nil)
            }
            return
        }

        let frontmostName = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let settingsIsFrontmost = frontmostName == "System Settings"
            || frontmostName == "System Preferences"
        guard settingsIsFrontmost, systemSettingsWindowFrame() != nil else {
            settingsSeenAt = nil
            if panel.isVisible {
                panel.orderOut(nil)
                panel.alphaValue = 0
            }
            return
        }

        if settingsSeenAt == nil {
            settingsSeenAt = Date()
        }
        guard panel.isVisible
            || Date().timeIntervalSince(settingsSeenAt ?? .distantFuture) > 0.45 else {
            return
        }

        position(panel)
        guard !panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    private func position(_ panel: NSPanel) {
        guard let settingsFrame = systemSettingsWindowFrame() else { return }

        let sidebarWidth: CGFloat = 215
        let contentInset: CGFloat = 20
        let width = max(330, settingsFrame.width - sidebarWidth - contentInset * 2)
        let x = settingsFrame.minX + sidebarWidth + contentInset
        let height = cardHeight(panel, width: width)
        let y = settingsFrame.minY + 18
        panel.setFrame(
            NSRect(x: x, y: y, width: width, height: height),
            display: true
        )
    }

    private func cardHeight(_ panel: NSPanel, width: CGFloat) -> CGFloat {
        if abs(model.cardWidth - width) > 0.5 {
            model.cardWidth = width
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        return max(92, panel.contentView?.fittingSize.height ?? 0)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 116),
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
    @Published var kind: KeyboardPermissionKind = .inputMonitoring
    @Published var cardWidth: CGFloat = 360
}

private struct PermissionDragGuideCard: View {
    @ObservedObject var model: PermissionDragGuideModel
    let onClose: () -> Void
    let onAcceptedDrop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrowIsRaised = false

    private var appURL: URL { Bundle.main.bundleURL }
    private var appIcon: NSImage { NSWorkspace.shared.icon(forFile: appURL.path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.58, green: 0.48, blue: 0.94))
                    .offset(y: arrowIsRaised ? -3 : 2)
                    .opacity(arrowIsRaised ? 0.4 : 1)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                        value: arrowIsRaised
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Drag KeySwitch into the list above")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Then turn it on to allow \(model.kind.title).")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Dismiss")
            }

            HStack(spacing: 10) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("KeySwitch")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Drag this app into the permission list")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(9)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            }
            .overlay(
                AppBundleDragSource(fileURL: appURL, onAcceptedDrop: onAcceptedDrop)
            )
        }
        .padding(12)
        .frame(width: model.cardWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .onAppear {
            if !reduceMotion {
                arrowIsRaised = true
            }
        }
    }
}
