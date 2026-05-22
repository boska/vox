import Foundation

struct ElevenVoice: Identifiable, Hashable, Codable {
    let voice_id: String
    let name: String
    var id: String { voice_id }
}

struct ElevenLabsAPI {
    static func fetchVoices(apiKey: String) async throws -> [ElevenVoice] {
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/voices")!)
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct Response: Codable { let voices: [ElevenVoice] }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.voices.sorted { $0.name < $1.name }
    }
}
