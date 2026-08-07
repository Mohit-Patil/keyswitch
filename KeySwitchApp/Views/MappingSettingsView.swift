import SwiftUI

struct MappingSettingsView: View {
    let model: AppModel
    @State private var editorTarget: MicroSettingsEditorTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader
                connectionCard
                lightingCard
                layoutSection
                optionsSection
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $editorTarget) { target in
            MicroSettingsEditorSheet(model: model, target: target)
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Codex Micro")
                .font(.system(size: 25, weight: .bold))
            Text("Assign Mac keys to Micro controls. Keycaps and actions stay synced with Codex.")
                .foregroundStyle(.secondary)
        }
    }

    private var connectionCard: some View {
        MicroSettingsCard {
            SettingsValueRow(
                title: "Connection",
                detail: "The active Codex desktop bridge; reconnects automatically",
                systemImage: "cable.connector",
                value: model.bridgeStatus.title,
                valueColor: model.bridgeStatus == .connected ? .green : .secondary
            ) {
                model.reconnectBridge()
            }

            Divider()

            SettingsValueRow(
                title: "Codex layout",
                detail: "Mirrors keycaps and control modes from the official Codex Micro settings",
                systemImage: "arrow.triangle.2.circlepath",
                value: model.hasLiveCodexMicroLayout ? "Synced" : "Waiting",
                valueColor: model.hasLiveCodexMicroLayout ? .green : .orange
            ) {
                if model.bridgeStatus == .connected {
                    model.openCodexMicroSettings()
                } else {
                    model.reconnectBridge()
                }
            }

            Divider()

            SettingsValueRow(
                title: "Input Monitoring",
                detail: "Allows KeySwitch to receive physical keyboard input",
                systemImage: "keyboard.badge.eye",
                value: model.permissions.inputMonitoringGranted ? "Granted" : "Required",
                valueColor: model.permissions.inputMonitoringGranted ? .green : .orange
            ) {
                if model.permissions.inputMonitoringGranted {
                    model.refreshPermissions()
                } else {
                    PermissionService.openInputMonitoringSettings()
                }
            }

            Divider()

            SettingsValueRow(
                title: "Accessibility",
                detail: "Allows the active keyboard layer to intercept and replace keys",
                systemImage: "accessibility",
                value: model.permissions.accessibilityGranted ? "Granted" : "Required",
                valueColor: model.permissions.accessibilityGranted ? .green : .orange
            ) {
                if model.permissions.accessibilityGranted {
                    model.refreshPermissions()
                } else {
                    PermissionService.openAccessibilitySettings()
                }
            }

            Divider()

            SettingsValueRow(
                title: "Keyboard capture",
                detail: "Confirms the remapping event tap is currently running",
                systemImage: "keyboard.fill",
                value: model.eventTapIsActive ? "Active" : "Retry",
                valueColor: model.eventTapIsActive ? .green : .orange
            ) {
                if model.eventTapIsActive {
                    model.refreshPermissions()
                } else {
                    model.retryKeyboardAccess()
                }
            }
        }
    }

    private var lightingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lighting")
                .font(.headline)

            MicroSettingsCard {
                HStack(alignment: .center, spacing: 18) {
                    SettingsRowLabel(
                        title: "Brightness",
                        detail: "Adjusts the brightness of all virtual Codex Micro lighting"
                    )

                    Spacer(minLength: 24)

                    Slider(
                        value: Binding(
                            get: { model.configuration.lightingBrightness },
                            set: { model.configuration.lightingBrightness = $0 }
                        ),
                        in: 0...1
                    )
                    .frame(width: 210)

                    Text(model.configuration.lightingBrightness, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }

                Divider()

                HStack(spacing: 18) {
                    SettingsRowLabel(
                        title: "Animated agent lighting",
                        detail: "Adds the orbiting rim and pulse to selected or working agents. Off by default for smoother motion and lower energy use."
                    )

                    Spacer(minLength: 24)

                    Toggle(
                        "Animated agent lighting",
                        isOn: Binding(
                            get: { model.configuration.animatedAgentLighting },
                            set: { model.configuration.animatedAgentLighting = $0 }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                Divider()

                HStack(spacing: 18) {
                    SettingsRowLabel(
                        title: "Auto-dim",
                        detail: "Turns lighting off after inactivity and restores it on the next key or agent update"
                    )

                    Spacer(minLength: 24)

                    Picker(
                        "Auto-dim",
                        selection: Binding(
                            get: { model.configuration.autoDimTimeout },
                            set: { model.configuration.autoDimTimeout = $0 }
                        )
                    ) {
                        ForEach(AutoDimTimeout.allCases) { timeout in
                            Text(timeout.title).tag(timeout)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }
        }
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Layout")
                    .font(.headline)
                Spacer()
                Button("Reset key mappings") {
                    model.resetMappings()
                }
                .buttonStyle(.borderless)
            }

            MicroSettingsCard(contentPadding: 16) {
                VStack(spacing: 10) {
                    MicroHUDView(
                        model: model,
                        continuousLightingMotionEnabled: model.configuration.animatedAgentLighting
                    ) { control in
                        openEditor(for: control)
                    }
                    .scaleEffect(0.8)
                    .frame(height: 312)

                    Label(
                        "Click a control to assign its Mac key. Change keycaps and actions in Codex.",
                        systemImage: "cursorarrow.click.2"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    AgentLightingLegend()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Options")
                .font(.headline)

            MicroSettingsCard {
                EditorOptionRow(
                    title: "Agent keys",
                    detail: "The six Mac keys follow the task source configured in Codex",
                    value: model.codexMicroLayout.agentSourceTitle
                ) {
                    model.openCodexMicroSettings()
                }

                Divider()

                EditorOptionRow(
                    title: "Knob",
                    detail: "Assign the turn and press keys; behavior is controlled by Codex",
                    value: model.codexMicroLayout.encoderModeTitle
                ) {
                    editorTarget = .dial
                }

                Divider()

                EditorOptionRow(
                    title: "Analog stick",
                    detail: "Assign the four Mac keys; each direction's action is controlled by Codex",
                    value: "Codex actions"
                ) {
                    editorTarget = .stick
                }

                Divider()

                EditorOptionRow(
                    title: "Microphone key",
                    detail: "Assign its Mac key; voice behavior is controlled by Codex",
                    value: model.codexMicroLayout.voiceButtonModeTitle
                ) {
                    editorTarget = .key(.pushToTalk)
                }

                Divider()

                EditorOptionRow(
                    title: "Microphone layout",
                    detail: "Combined or separate microphone switches, controlled by Codex",
                    value: model.codexMicroLayout.separateMicrophoneKeys
                        ? "Separate"
                        : "Combined"
                ) {
                    model.openCodexMicroSettings()
                }

                Divider()

                HStack(spacing: 18) {
                    SettingsRowLabel(
                        title: "Focus Codex with a single tap",
                        detail: "Bring the assigned task and Codex window forward with one agent-key press"
                    )
                    Spacer()
                    Toggle(
                        "Focus Codex with a single tap",
                        isOn: Binding(
                            get: { model.configuration.focusCodexOnSingleTap },
                            set: { model.setFocusCodexOnSingleTap($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
        }
    }

    private func openEditor(for control: MicroControl) {
        if control.isDialControl {
            editorTarget = .dial
        } else if control.isStickControl {
            editorTarget = .stick
        } else {
            editorTarget = .key(control)
        }
    }
}

private struct MicroSettingsCard<Content: View>: View {
    var contentPadding: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 14) {
            content()
        }
        .padding(contentPadding)
        .background(.quaternary.opacity(0.34), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .fontWeight(.medium)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let value: String
    let valueColor: Color
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            SettingsRowLabel(title: title, detail: detail)
            Spacer()
            Button(action: action) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(valueColor)
                        .frame(width: 7, height: 7)
                    Text(value)
                }
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct EditorOptionRow: View {
    let title: String
    let detail: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                SettingsRowLabel(title: title, detail: detail)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AgentLightingLegend: View {
    private let statuses: [AgentLightStatus] = [
        .idle,
        .working,
        .unread,
        .awaitingApproval,
        .error,
        .off,
    ]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 112), spacing: 12)],
            alignment: .leading,
            spacing: 7
        ) {
            ForEach(statuses, id: \.self) { status in
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color(agentLightStatus: status))
                        .frame(width: 10, height: 10)
                        .overlay {
                            Circle().stroke(.white.opacity(0.28), lineWidth: 0.7)
                        }
                        .shadow(
                            color: Color(agentLightStatus: status)
                                .opacity(status == .off ? 0 : 0.68),
                            radius: 4
                        )
                    Text(label(for: status))
                        .lineLimit(1)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func label(for status: AgentLightStatus) -> String {
        switch status {
        case .working: "Thinking"
        case .unread: "Complete"
        case .awaitingApproval, .awaitingResponse: "Requires input"
        case .off: "No assigned agent"
        default: status.title
        }
    }
}

private extension Color {
    init(agentLightStatus status: AgentLightStatus) {
        let rgb = status.packedRGB
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
