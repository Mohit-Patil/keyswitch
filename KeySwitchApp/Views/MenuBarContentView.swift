import AppKit
import SwiftUI

struct MenuBarContentView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(model.layerIsActive ? Color.accentColor : .secondary.opacity(0.15))
                    Image(systemName: "keyboard")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(model.layerIsActive ? .white : .primary)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text("KeySwitch")
                        .font(.headline)
                    Text(
                        model.layerIsActive
                            ? "Layer active"
                            : "\(model.configuration.activationShortcut.displayName) · \(model.configuration.activationMode.title)"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Divider()

            StatusRow(
                title: "Keyboard capture",
                value: model.eventTapIsActive ? "Ready" : "Permission needed",
                color: model.eventTapIsActive ? .green : .orange
            )
            StatusRow(
                title: "Codex bridge",
                value: model.bridgeStatus.title,
                color: model.bridgeStatus == .connected ? .green : .secondary
            )

            Text(model.lastActionDescription)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Divider()

            Button {
                model.toggleLayerFromMenu()
            } label: {
                Label(
                    model.layerIsActive ? "Turn Layer Off" : "Turn Layer On",
                    systemImage: model.layerIsActive ? "pause.circle" : "play.circle"
                )
            }

            if !model.eventTapIsActive {
                Button {
                    model.retryKeyboardAccess()
                } label: {
                    Label("Retry Keyboard Access", systemImage: "lock.open")
                }
            }

            Button {
                model.showFirstRunSetup()
            } label: {
                Label("Codex Micro Setup…", systemImage: "keyboard.badge.ellipsis")
            }

            Button {
                presentSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit KeySwitch", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .padding(16)
        .frame(width: 310)
    }

    private func presentSettings() {
        openSettings()
        NSApplication.shared.activate(ignoringOtherApps: true)

        // SwiftUI can create the Settings window as the menu-bar panel is
        // resigning key status. Bring that window forward on the next turn.
        DispatchQueue.main.async {
            let application = NSApplication.shared
            application.activate(ignoringOtherApps: true)
            application.windows
                .first(where: {
                    $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
                })?
                .makeKeyAndOrderFront(nil)
        }
    }
}

private struct StatusRow: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
