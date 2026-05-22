import Foundation

struct VoxConfig: Codable {
    var elevenLabsKey: String = ""
    var voiceId: String = "jsCqWAovK2LkecY7zXl4"
    var voiceName: String = "Hana"

    static let configURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/vox")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    static func load() -> VoxConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(VoxConfig.self, from: data)
        else { return VoxConfig() }
        return config
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: VoxConfig.configURL, options: .atomic)
    }
}
