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

                TextField(
                    "Chromium debugging port",
                    value: Binding(
                        get: { model.configuration.debugPort },
                        set: { model.configuration.debugPort = $0 }
                    ),
                    format: .number
                )

                Button("Open Codex Micro Settings") {
                    model.openCodexMicroSettings()
                }
                .disabled(model.bridgeStatus != .connected)

                Button("Run Codex Micro Setup…") {
                    model.showFirstRunSetup()
                }
            }

            Section("Input health") {
                LabeledContent("Input Monitoring") {
                    Text(model.permissions.inputMonitoringGranted ? "Granted" : "Required")
                        .foregroundStyle(model.permissions.inputMonitoringGranted ? .green : .orange)
                }
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
