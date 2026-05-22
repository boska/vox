import SwiftUI

struct MenuBarIcon: View {
    let status: VoxStatus
    @State private var frame = 0

    private let timer = Timer.publish(every: 0.18, on: .main, in: .common).autoconnect()

    private static let listeningFrames = ["·∙○", "∙○◎", "○◎●", "∙○◎", "·∙○"]
    private static let speakingFrames  = ["▁▂▃", "▂▄▅", "▃▅▇", "▄▆█", "▃▅▇", "▂▄▅"]

    private var label: String {
        switch status {
        case .idle:
            return "·"
        case .listening:
            return Self.listeningFrames[frame % Self.listeningFrames.count]
        case .speaking:
            return Self.speakingFrames[frame % Self.speakingFrames.count]
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .onReceive(timer) { _ in
                if status != .idle { frame += 1 }
            }
            .onChange(of: status) { _ in frame = 0 }
    }
}
