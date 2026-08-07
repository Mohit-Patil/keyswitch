import AppKit
import SwiftUI

struct KeyRecorderSheet: View {
    let model: AppModel
    let control: MicroControl
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: control.systemImage)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 6) {
                Text("Set key for \(control.title)")
                    .font(.title2.bold())
                Text("Press any keyboard key or modifier. Fn stays available for macOS and activation shortcuts.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            KeyRecorderView { key in
                model.assign(key, to: control)
                dismiss()
            } onCancel: {
                dismiss()
            }
            .frame(height: 110)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Clear mapping") {
                    model.assign(nil, to: control)
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}

struct KeyRecorderView: NSViewRepresentable {
    let onCapture: (PhysicalKey) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class KeyRecorderNSView: NSView {
    var onCapture: ((PhysicalKey) -> Void)?
    var onCancel: (() -> Void)?
    private var hasCaptured = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard !hasCaptured else { return }
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        capture(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard !hasCaptured,
              PhysicalKey.modifierKeyCodes.contains(event.keyCode),
              modifierIsDown(event) else { return }
        capture(event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let text = "Press a key…" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }

    private func capture(_ event: NSEvent) {
        guard let key = PhysicalKey.from(event: event) else { return }
        hasCaptured = true
        onCapture?(key)
    }

    private func modifierIsDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 54, 55:
            event.modifierFlags.contains(.command)
        case 56, 60:
            event.modifierFlags.contains(.shift)
        case 57:
            event.modifierFlags.contains(.capsLock)
        case 58, 61:
            event.modifierFlags.contains(.option)
        case 59, 62:
            event.modifierFlags.contains(.control)
        default:
            false
        }
    }
}
