import AppKit
import SwiftUI

struct ActivationShortcutEditor: View {
    let model: AppModel
    let initialShortcut: ActivationShortcut

    @Environment(\.dismiss) private var dismiss
    @State private var selectedModifiers: Set<ActivationModifier>
    @State private var selectedKey: PhysicalKey?
    @State private var isRecording = false
    @FocusState private var recordButtonIsFocused: Bool

    init(model: AppModel, initialShortcut: ActivationShortcut) {
        self.model = model
        self.initialShortcut = initialShortcut
        _selectedModifiers = State(initialValue: initialShortcut.modifiers)
        _selectedKey = State(initialValue: initialShortcut.key)
    }

    private var shortcut: ActivationShortcut {
        ActivationShortcut(modifiers: selectedModifiers, key: selectedKey)
    }

    private var conflictingControls: [MicroControl] {
        model.configuration.bindings.compactMap { binding in
            guard let key = binding.physicalKey,
                  shortcut.contains(keyCode: key.keyCode) else { return nil }
            return binding.control
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 6) {
                Text("Choose an activation shortcut")
                    .font(.title2.bold())
                Text("Use one standard key, modifiers only, or any key combination. Fn + Control remains the recommended default.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            HStack(spacing: 9) {
                ForEach(ActivationModifier.allCases) { modifier in
                    ModifierChoice(
                        modifier: modifier,
                        isSelected: selectedModifiers.contains(modifier)
                    ) {
                        stopRecording()
                        toggle(modifier)
                    }
                }
            }

            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keyboard key")
                            .font(.headline)
                        Text("Record the complete shortcut. Held modifiers replace the choices above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if selectedKey != nil, !isRecording {
                        Button("Clear Key") {
                            selectedKey = nil
                        }
                    }

                    Button(isRecording ? "Cancel Recording" : selectedKey == nil ? "Record Key" : "Change Key") {
                        if isRecording {
                            stopRecording(restoreFocus: true)
                        } else {
                            startRecording()
                        }
                    }
                    .focused($recordButtonIsFocused)
                    .disabled(!model.keyboardAccessIsReady && !isRecording)
                }

                if !model.keyboardAccessIsReady, !isRecording {
                    Label(
                        "Grant Accessibility permission before recording a global shortcut.",
                        systemImage: "lock.trianglebadge.exclamationmark"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isRecording {
                    VStack(spacing: 6) {
                        Image(systemName: "record.circle")
                            .font(.title2)
                        Text("Press and release the complete shortcut…")
                            .font(.headline)
                        Text("System shortcuts are captured here without opening their normal action.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .contentShape(Rectangle())
                    .onAppear {
                        let didBeginCapture = model.beginActivationShortcutCapture(
                            onCapture: { key, modifiers in
                                guard isRecording else { return }
                                selectedKey = key
                                selectedModifiers = modifiers
                                stopRecording(restoreFocus: true)
                            },
                            onCancel: {
                                stopRecording(restoreFocus: true)
                            }
                        )
                        if !didBeginCapture {
                            stopRecording(restoreFocus: true)
                        }
                    }
                    .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                    }
                    .accessibilityLabel("Recording activation shortcut")
                    .accessibilityValue("Waiting for a standard keyboard key")
                    .accessibilityHint("Press and release the complete shortcut. Held modifiers are included.")
                } else {
                    HStack(spacing: 9) {
                        Image(systemName: selectedKey == nil ? "keyboard" : "keyboard.fill")
                            .foregroundStyle(selectedKey == nil ? Color.secondary : Color.accentColor)
                        Text(selectedKey.map { "Recorded key: \($0.displayName)" } ?? "No regular key — modifiers only")
                            .foregroundStyle(selectedKey == nil ? Color.secondary : Color.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 50)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 11))
                }
            }

            VStack(spacing: 9) {
                Text(shortcut.isValid ? "Your shortcut" : "Choose a key or modifier")
                    .font(.caption)
                    .foregroundStyle(shortcut.isValid ? Color.secondary : Color.orange)

                ActivationShortcutKeyCaps(shortcut: shortcut)
                    .frame(height: 34)
            }

            if selectedKey != nil, selectedModifiers.isEmpty {
                Label(
                    "This key will be consumed globally while KeySwitch is running. You can always change it from the menu bar.",
                    systemImage: "info.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }

            if !conflictingControls.isEmpty {
                Label(
                    "The activation shortcut takes priority over \(conflictingControls.map(\.title).joined(separator: ", ")). Remap those controls if needed.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }

            Divider()

            HStack {
                Button("Use Fn + Control") {
                    stopRecording()
                    selectedModifiers = ActivationShortcut.standard.modifiers
                    selectedKey = nil
                }

                Spacer()

                Button("Cancel") {
                    stopRecording()
                    dismiss()
                }

                Button("Use Shortcut") {
                    guard shortcut.isValid else { return }
                    stopRecording()
                    model.configuration.activationShortcut = shortcut
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!shortcut.isValid || isRecording)
            }
        }
        .padding(24)
        .frame(width: 570)
        .onDisappear {
            stopRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stopRecording()
        }
        .onChange(of: model.keyboardAccessIsReady) { _, isReady in
            if !isReady {
                stopRecording()
            }
        }
    }

    private func startRecording() {
        guard !isRecording, model.keyboardAccessIsReady else { return }
        isRecording = true
    }

    private func stopRecording(restoreFocus: Bool = false) {
        guard isRecording else { return }
        isRecording = false
        model.endActivationShortcutCapture()
        if restoreFocus {
            DispatchQueue.main.async {
                recordButtonIsFocused = true
            }
        }
    }

    private func toggle(_ modifier: ActivationModifier) {
        if selectedModifiers.contains(modifier) {
            selectedModifiers.remove(modifier)
        } else {
            selectedModifiers.insert(modifier)
        }
    }
}

struct ActivationShortcutKeyCaps: View {
    let shortcut: ActivationShortcut

    var body: some View {
        HStack(spacing: 5) {
            ForEach(shortcut.orderedModifiers) { modifier in
                ShortcutKeyCap(text: modifier.symbol, accessibilityName: modifier.title)
            }

            if let key = shortcut.key {
                ShortcutKeyCap(text: key.displayName, accessibilityName: key.displayName)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(shortcut.isValid ? shortcut.displayName : "No shortcut selected")
    }
}

private struct ShortcutKeyCap: View {
    let text: String
    let accessibilityName: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .frame(minWidth: 27, minHeight: 24)
            .padding(.horizontal, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .accessibilityLabel(accessibilityName)
    }
}

private struct ModifierChoice: View {
    let modifier: ActivationModifier
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Text(modifier.symbol)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(modifier.title)
                    .font(.caption)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(width: 84, height: 62)
            .background(
                isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.white.opacity(0.22) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(modifier.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
