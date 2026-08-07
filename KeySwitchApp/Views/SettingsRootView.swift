import SwiftUI

struct SettingsRootView: View {
    let model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView(model: model)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            MappingSettingsView(model: model)
                .tabItem {
                    Label("Codex Micro", systemImage: "keyboard")
                }

            ConnectionSettingsView(model: model)
                .tabItem {
                    Label("Connection", systemImage: "cable.connector")
                }
        }
        .frame(width: 780, height: 720)
    }
}
