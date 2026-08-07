import SwiftUI

enum MicroSettingsEditorTarget: Identifiable {
    case key(MicroControl)
    case dial
    case stick

    var id: String {
        switch self {
        case .key(let control): "key-\(control.rawValue)"
        case .dial: "dial"
        case .stick: "stick"
        }
    }
}

struct MicroSettingsEditorSheet: View {
    let model: AppModel
    let target: MicroSettingsEditorTarget

    var body: some View {
        switch target {
        case .key(let control):
            if control.supportsKeycapAppearance {
                CodexSlotMappingEditorSheet(model: model, control: control)
            } else {
                SimpleMappingEditorSheet(model: model, controls: [control], title: control.title)
            }
        case .dial:
            SimpleMappingEditorSheet(
                model: model,
                controls: [.dialPrevious, .dialNext, .dialPress],
                title: "Knob"
            )
        case .stick:
            SimpleMappingEditorSheet(
                model: model,
                controls: [.stickUp, .stickRight, .stickDown, .stickLeft],
                title: "Analog stick"
            )
        }
    }
}

struct MicroKeycapGlyph: View {
    let keycap: MicroKeycap
    var size: CGFloat = 27

    var body: some View {
        Group {
            if keycap == .codex {
                ZStack {
                    Image(systemName: "seal")
                        .font(.system(size: size, weight: .medium))
                    Image(systemName: "ellipsis")
                        .font(.system(size: size * 0.27, weight: .bold))
                }
            } else if let systemImage = keycap.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: size, weight: .regular))
            } else if let textGlyph = keycap.textGlyph {
                Text(textGlyph)
                    .font(.system(size: size * 0.54, weight: .medium, design: .monospaced))
            } else {
                Circle()
                    .stroke(.secondary.opacity(0.35), lineWidth: 1.2)
                    .frame(width: size * 0.72, height: size * 0.72)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CodexSlotMappingEditorSheet: View {
    let model: AppModel
    let control: MicroControl

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhysicalKey: PhysicalKey?
    @State private var isRecording = false

    init(model: AppModel, control: MicroControl) {
        self.model = model
        self.control = control
        _selectedPhysicalKey = State(initialValue: model.binding(for: control).physicalKey)
    }

    private var keycap: MicroKeycap {
        model.keycap(for: control)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 14) {
                syncedKeycapCard
                keyboardMappingRow

                if isRecording {
                    recorder
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            Divider()

            HStack {
                Button("Clear mapping") {
                    selectedPhysicalKey = nil
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    model.assign(selectedPhysicalKey, to: control)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.18), value: isRecording)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Map \(control.microKey)")
                    .font(.title2.bold())
                Text("KeySwitch assigns the Mac key. Codex controls this slot's keycap and action.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(24)
    }

    private var syncedKeycapCard: some View {
        HStack(spacing: 16) {
            MicroKeycapGlyph(keycap: keycap, size: 31)
                .foregroundStyle(.white)
                .frame(width: 66, height: 66)
                .background(
                    Color(red: 0.11, green: 0.12, blue: 0.15),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(keycap.title)
                    .font(.headline)
                Text("\(control.microKey) · \(keycap.label)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Label(
                    model.hasLiveCodexMicroLayout ? "Synced from Codex" : "Waiting for Codex",
                    systemImage: model.hasLiveCodexMicroLayout
                        ? "checkmark.circle.fill"
                        : "arrow.triangle.2.circlepath"
                )
                .font(.caption)
                .foregroundStyle(model.hasLiveCodexMicroLayout ? .green : .secondary)
            }

            Spacer()

            Button("Open Codex Settings") {
                model.openCodexMicroSettings()
            }
            .buttonStyle(.bordered)
            .disabled(model.bridgeStatus != .connected)
        }
        .padding(16)
        .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 12))
    }

    private var keyboardMappingRow: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Keyboard key")
                    .fontWeight(.semibold)
                Text("Used while the KeySwitch layer is active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isRecording.toggle()
            } label: {
                HStack(spacing: 7) {
                    Text(selectedPhysicalKey?.displayName ?? "Choose")
                    Image(systemName: isRecording ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 12))
    }

    private var recorder: some View {
        KeyRecorderView { key in
            selectedPhysicalKey = key
            isRecording = false
        } onCancel: {
            isRecording = false
        }
        .frame(height: 82)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.55), lineWidth: 1.5)
        }
        .accessibilityLabel("Press the keyboard key to assign")
    }
}

private struct SimpleMappingEditorSheet: View {
    let model: AppModel
    let controls: [MicroControl]
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var workingBindings: [MicroControl: PhysicalKey?]
    @State private var recordingControl: MicroControl?

    init(model: AppModel, controls: [MicroControl], title: String) {
        self.model = model
        self.controls = controls
        self.title = title
        _workingBindings = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: controls.map { ($0, model.binding(for: $0).physicalKey) }
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Edit \(title.lowercased())")
                        .font(.title2.bold())
                    Text("Choose the keyboard keys used while the KeySwitch layer is active.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(24)

            VStack(spacing: 10) {
                ForEach(controls) { control in
                    HStack {
                        Label(control.title, systemImage: control.systemImage)
                        Spacer()
                        Button(workingBindings[control]??.displayName ?? "Choose") {
                            recordingControl = control
                        }
                        .buttonStyle(.bordered)
                        Button {
                            workingBindings[control] = nil
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Clear mapping")
                    }
                    .padding(13)
                    .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 11))
                }

                if let recordingControl {
                    KeyRecorderView { key in
                        workingBindings[recordingControl] = key
                        self.recordingControl = nil
                    } onCancel: {
                        self.recordingControl = nil
                    }
                    .frame(height: 82)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    for control in controls {
                        model.assign(workingBindings[control] ?? nil, to: control)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
