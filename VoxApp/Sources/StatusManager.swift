import Foundation
import Combine
import ServiceManagement

enum VoxStatus: String {
    case idle, listening, speaking

    var icon: String {
        switch self {
        case .idle:      return "mic.slash"
        case .listening: return "mic.fill"
        case .speaking:  return "speaker.wave.2.fill"
        }
    }
}

final class StatusManager: ObservableObject {
    @Published var status: VoxStatus = .idle
    @Published var launchAtLogin: Bool = false

    var icon: String { status.icon }

    private let statusFile = URL(fileURLWithPath: "/tmp/vox-status")
    private var timer: AnyCancellable?

    init() {
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.poll() }

        // Defer SMAppService check — querying at init causes port errors before the app is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func poll() {
        guard let raw = try? String(contentsOf: statusFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let s = VoxStatus(rawValue: raw) else { return }
        if s != status { status = s }
    }

    func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                launchAtLogin = false
            } else {
                try service.register()
                launchAtLogin = true
            }
        } catch {
            // SMAppService requires the app to be in /Applications to register
            print("[VoxApp] LaunchAtLogin error: \(error.localizedDescription)")
        }
    }
}
