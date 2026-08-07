import SwiftUI

struct ActivationShortcutEditor: View {
    let model: AppModel
    let initialShortcut: ActivationShortcut

    @Environment(\.dismiss) private var dismiss
    @State private var selectedModifiers: Set<ActivationModifier>

    init(model: AppModel, initialShortcut: ActivationShortcut) {
        self.model = model
        self.initialShortcut = initialShortcut
        _selectedModifiers = State(initialValue: initialShortcut.modifiers)
    }

    private var shortcut: ActivationShortcut {
        ActivationShortcut(modifiers: selectedModifiers)
    }

    private var conflictingControls: [MicroControl] {
        model.configuration.bindings.compactMap { binding in
            guard let key = binding.physicalKey,
                  shortcut.contains(keyCode: key.keyCode) else { return nil }
            return binding.control
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 6) {
                Text("Choose an activation shortcut")
                    .font(.title2.bold())
                Text("Select at least two modifier keys. Modifier-only chords avoid typing a character or triggering an app command.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
            }

            HStack(spacing: 9) {
                ForEach(ActivationModifier.allCases) { modifier in
                    ModifierChoice(
                        modifier: modifier,
                        isSelected: selectedModifiers.contains(modifier)
                    ) {
                        toggle(modifier)
                    }
                }
            }

            VStack(spacing: 9) {
                Text(shortcut.isValid ? "Your shortcut" : "Choose one more modifier")
                    .font(.caption)
                    .foregroundStyle(shortcut.isValid ? Color.secondary : Color.orange)

                ActivationShortcutKeyCaps(shortcut: shortcut)
                    .frame(height: 34)
            }

            if !conflictingControls.isEmpty {
                Label(
                    "Activation modifiers take priority over \(conflictingControls.map(\.title).joined(separator: ", ")). Remap those controls if needed.",
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
                    selectedModifiers = ActivationShortcut.standard.modifiers
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Use Shortcut") {
                    guard shortcut.isValid else { return }
                    model.configuration.activationShortcut = shortcut
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!shortcut.isValid)
            }
        }
        .padding(24)
        .frame(width: 540)
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
                Text(modifier.symbol)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(minWidth: 27, minHeight: 24)
                    .padding(.horizontal, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    }
                    .accessibilityLabel(modifier.title)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(shortcut.displayName)
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
