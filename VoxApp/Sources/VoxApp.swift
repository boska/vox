import SwiftUI

@main
struct VoxApp: App {
    @StateObject private var status = StatusManager()

    var body: some Scene {
        MenuBarExtra {
            
            MenuBarView()
                .environmentObject(status)
        } label: {
            MenuBarIcon(status: status.status)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}
