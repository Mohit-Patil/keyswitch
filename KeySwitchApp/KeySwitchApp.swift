import SwiftUI

@main
@MainActor
struct KeySwitchApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            Image(systemName: model.layerIsActive ? "keyboard.fill" : "keyboard")
                .accessibilityLabel(model.layerIsActive ? "KeySwitch layer active" : "KeySwitch")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView(model: model)
        }
    }
}
