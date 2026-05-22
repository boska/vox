import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var status: StatusManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: status.icon)
                Text(status.status.rawValue.capitalized)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            Divider()

            Toggle("Launch at Login", isOn: Binding(
                get: { status.launchAtLogin },
                set: { _ in status.toggleLaunchAtLogin() }
            ))

            Divider()

            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")

            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(8)
    }
}
