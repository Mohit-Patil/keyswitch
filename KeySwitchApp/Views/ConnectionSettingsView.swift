import SwiftUI

struct ConnectionSettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Codex connection") {
                HStack {
                    Label(
                        model.bridgeStatus.title,
                        systemImage: model.bridgeStatus == .connected
                            ? "checkmark.circle.fill"
                            : "cable.connector.slash"
                    )
                    .foregroundStyle(model.bridgeStatus == .connected ? .green : .secondary)
                    Spacer()
                    Button("Reconnect") {
                        model.reconnectBridge()
                    }
                }

                Text("KeySwitch retries the local Codex connection every two seconds if Codex relaunches or the renderer changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Codex Micro layout") {
                    Text(model.hasLiveCodexMicroLayout ? "Synced" : "Waiting")
                        .foregroundStyle(model.hasLiveCodexMicroLayout ? .green : .orange)
                }

                DebugPortField(model: model)

                Button("Open Codex Micro Settings") {
                    model.openCodexMicroSettings()
                }
                .disabled(model.bridgeStatus != .connected)

                Button("Run Codex Micro Setup…") {
                    model.showFirstRunSetup()
                }
            }

            Section("Input health") {
                LabeledContent("Accessibility") {
                    Text(model.permissions.accessibilityGranted ? "Granted" : "Required")
                        .foregroundStyle(model.permissions.accessibilityGranted ? .green : .orange)
                }
                LabeledContent("Keyboard capture") {
                    Text(model.eventTapIsActive ? "Active" : "Stopped")
                        .foregroundStyle(model.eventTapIsActive ? .green : .orange)
                }

                Button("Refresh and retry keyboard capture") {
                    model.retryKeyboardAccess()
                }
            }

            Section("About this bridge") {
                Text("KeySwitch connects to your normal Codex desktop profile over a local-only debugging port. The setup assistant can restart Codex once with that connection enabled; it does not create a second or isolated Codex profile.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct DebugPortField: View {
    let model: AppModel

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(model: AppModel) {
        self.model = model
        _draft = State(initialValue: String(model.configuration.debugPort))
    }

    private var parsedPort: Int? {
        Int(draft)
    }

    private var validationMessage: String? {
        guard !draft.isEmpty else {
            return "Enter a port from 1 through 65535."
        }
        guard let parsedPort, AppConfiguration.isValidDebugPort(parsedPort) else {
            return "The port must be a number from 1 through 65535."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField("Chromium debugging port", text: $draft)
                .monospacedDigit()
                .focused($isFocused)
                .onChange(of: draft) { _, newValue in
                    let digits = newValue.filter { "0123456789".contains($0) }
                    if digits != newValue {
                        draft = digits
                    }
                }
                .onSubmit {
                    applyDraftIfValid()
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        applyDraftIfValid()
                    }
                }
                .onChange(of: model.configuration.debugPort) { _, port in
                    if !isFocused {
                        draft = String(port)
                    }
                }
                .accessibilityValue(draft)
                .accessibilityHint(
                    validationMessage
                        ?? "Enter a local debugging port from 1 through 65535"
                )

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Debugging port error: \(validationMessage)")
            } else if parsedPort != model.configuration.debugPort {
                Text("Press Return or leave the field to apply this port.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func applyDraftIfValid() {
        guard let parsedPort, AppConfiguration.isValidDebugPort(parsedPort) else {
            return
        }
        draft = String(parsedPort)
        if model.configuration.debugPort != parsedPort {
            model.configuration.debugPort = parsedPort
        }
    }
}
