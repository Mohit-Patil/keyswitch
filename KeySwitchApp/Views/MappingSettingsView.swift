import SwiftUI

struct MappingSettingsView: View {
    let model: AppModel
    @State private var editorTarget: MicroSettingsEditorTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader
                codexOwnershipCard
                layoutSection
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
            Text("Assign Mac keys to Micro controls. Codex remains the source of truth for how every control behaves.")
                .foregroundStyle(.secondary)
        }
    }

    private var codexOwnershipCard: some View {
        MicroSettingsCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3)
                    .foregroundStyle(
                        model.hasLiveCodexMicroLayout ? Color.green : Color.orange
                    )
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 5) {
                    Text(
                        model.hasLiveCodexMicroLayout
                            ? "Synced with Codex"
                            : "Waiting for Codex"
                    )
                    .fontWeight(.semibold)

                    Text(
                        "Keycaps, actions, agent source, knob and stick behavior, microphone mode, lighting, and tap behavior are configured directly in Codex. KeySwitch only assigns the Mac keys that trigger those controls."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 18)

                Button("Open Codex Settings") {
                    model.openCodexMicroSettings()
                }
                .disabled(model.bridgeStatus != .connected)
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
                        "Click a control to assign its Mac key. The displayed keycaps and live state come from Codex.",
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
                        .fill(
                            status == .off
                                ? Color.clear
                                : Color(agentLightStatus: status)
                        )
                        .frame(width: 10, height: 10)
                        .overlay {
                            Circle().stroke(
                                status == .off
                                    ? Color.secondary.opacity(0.72)
                                    : Color.white.opacity(0.28),
                                lineWidth: status == .off ? 1 : 0.7
                            )
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
