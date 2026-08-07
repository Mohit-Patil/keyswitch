import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    let model: AppModel
    @State private var shortcutBeingEdited: ActivationShortcut?

    var body: some View {
        Form {
            Section("Layer activation") {
                HStack {
                    Text("Activation shortcut")
                    Spacer()
                    Button {
                        shortcutBeingEdited = model.configuration.activationShortcut
                    } label: {
                        ActivationShortcutKeyCaps(shortcut: model.configuration.activationShortcut)
                    }
                    .buttonStyle(.plain)
                    .help("Change activation shortcut")
                }

                Text("Fn by itself continues to work as the macOS Globe/emoji key. Only the complete shortcut activates KeySwitch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(
                    "Behavior",
                    selection: Binding(
                        get: { model.configuration.activationMode },
                        set: { model.configuration.activationMode = $0 }
                    )
                ) {
                    ForEach(ActivationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(model.configuration.activationMode.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(
                    "Auto-exit after inactivity",
                    selection: Binding(
                        get: { model.configuration.layerAutoExitTimeout },
                        set: { model.configuration.layerAutoExitTimeout = $0 }
                    )
                ) {
                    ForEach(LayerAutoExitTimeout.allCases) { timeout in
                        Text(timeout.title).tag(timeout)
                    }
                }

                Text(autoExitHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(
                    "Show the Codex Micro HUD",
                    isOn: Binding(
                        get: { model.configuration.showHUD },
                        set: { model.configuration.showHUD = $0 }
                    )
                )

                Picker(
                    "Expanded HUD size",
                    selection: Binding(
                        get: { model.configuration.expandedHUDSize },
                        set: { model.configuration.expandedHUDSize = $0 }
                    )
                ) {
                    ForEach(ExpandedHUDSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!model.configuration.showHUD)

                Text(
                    "\(model.configuration.expandedHUDSize.title) is "
                        + "\(Int(model.configuration.expandedHUDSize.sideLength)) × "
                        + "\(Int(model.configuration.expandedHUDSize.sideLength)) pt. "
                        + "Changing it briefly previews the real Micro at the top-right of your screen."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(
                    "Show agent status in the menu bar",
                    isOn: Binding(
                        get: { model.configuration.showMenuBarAgentStatus },
                        set: { model.configuration.showMenuBarAgentStatus = $0 }
                    )
                )

                Picker(
                    "Indicator size",
                    selection: Binding(
                        get: { model.configuration.menuBarIndicatorSize },
                        set: { model.configuration.menuBarIndicatorSize = $0 }
                    )
                ) {
                    ForEach(MenuBarIndicatorSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!model.configuration.showMenuBarAgentStatus)

                Text("Displays the six Codex agent states beside the KeySwitch icon. Size changes appear immediately in the actual menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(
                    "HUD appearance",
                    selection: Binding(
                        get: { model.configuration.hudAppearance },
                        set: { model.configuration.hudAppearance = $0 }
                    )
                ) {
                    ForEach(HUDAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!model.configuration.showHUD)

                Text("System follows your Mac appearance automatically. Light and Dark keep the HUD in the selected style.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(
                    "Block unmapped keys while the layer is active",
                    isOn: Binding(
                        get: { model.configuration.blockUnmappedKeys },
                        set: { model.configuration.blockUnmappedKeys = $0 }
                    )
                )
            }

            Section("Startup") {
                Toggle(
                    "Launch KeySwitch at login",
                    isOn: Binding(
                        get: { model.launchAtLoginState.isRequested },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
                .disabled(model.launchAtLoginState == .unavailable)

                Text(model.launchAtLoginState.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.launchAtLoginState == .requiresApproval {
                    Button("Open Login Items Settings") {
                        model.openLoginItemsSettings()
                    }
                }

                if let errorMessage = model.launchAtLoginErrorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Input Monitoring",
                    granted: model.permissions.inputMonitoringGranted,
                    action: PermissionService.openInputMonitoringSettings
                )
                PermissionRow(
                    title: "Accessibility",
                    granted: model.permissions.accessibilityGranted,
                    action: PermissionService.openAccessibilitySettings
                )

                HStack {
                    Button("Request and retry") {
                        model.retryKeyboardAccess()
                    }
                    Button("Refresh status") {
                        model.refreshPermissions()
                    }
                }
            }

            Section("Safety") {
                Text("Escape immediately turns off the keyboard layer. The inactivity timer and menu-bar control can also disable it at any time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            model.refreshLaunchAtLoginState()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            model.refreshLaunchAtLoginState()
        }
        .sheet(item: $shortcutBeingEdited) { shortcut in
            ActivationShortcutEditor(model: model, initialShortcut: shortcut)
        }
    }

    private var autoExitHelpText: String {
        if model.configuration.layerAutoExitTimeout == .never {
            return "The layer stays active until you release a held shortcut, press a toggled shortcut again, or use Escape."
        }

        return "The countdown pauses while a mapped key is held and restarts after every mapped action."
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Spacer()
            Text(granted ? "Granted" : "Required")
                .foregroundStyle(.secondary)
            Button("Open Settings", action: action)
        }
    }
}
