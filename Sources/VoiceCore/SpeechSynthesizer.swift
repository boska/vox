import AVFoundation
import Foundation

public class SpeechSynthesizer: NSObject {
    private let model = "eleven_multilingual_v2"
    private let voiceSettings: [String: Any] = [
        "stability": 0.35,
        "similarity_boost": 0.8,
        "style": 0.5,
        "use_speaker_boost": true
    ]

    private let fallback = AVSpeechSynthesizer()
    private var fallbackContinuation: CheckedContinuation<Void, Never>?
    private var audioPlayer: AVAudioPlayer?
    private var audioPlayerContinuation: CheckedContinuation<Void, Never>?

    public override init() {
        super.init()
        fallback.delegate = self
    }

    // 抓音頻 data（可並行呼叫）— reads config fresh each call for on-the-fly voice switching
    public func fetchAudio(_ text: String) async throws -> Data {
        let (elevenLabsKey, voiceId) = SpeechSynthesizer.loadConfig()
        guard !elevenLabsKey.isEmpty else { throw SynthError.noKey }
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)")!)
        req.httpMethod = "POST"
        req.setValue(elevenLabsKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["text": text, "model_id": model, "voice_settings": voiceSettings]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw SynthError.apiError(msg)
        }
        return data
    }

    // 播放已有的音頻 data
    public func playData(_ data: Data) async {
        await withCheckedContinuation { [weak self] continuation in
            guard let self else { continuation.resume(); return }
            do {
                let player = try AVAudioPlayer(data: data)
                self.audioPlayer = player
                self.audioPlayerContinuation = continuation
                player.delegate = self
                player.prepareToPlay()
                player.play()
            } catch {
                continuation.resume()
            }
        }
    }

    // 簡單一次性 speak（fallback 用）
    public func speakFallback(_ text: String, locale: String? = nil) async {
        let utterance = AVSpeechUtterance(string: text)
        let lang = locale ?? "zh-TW"
        utterance.voice = AVSpeechSynthesisVoice(language: lang)
        utterance.rate = 0.48
        await withCheckedContinuation { [weak self] cont in
            self?.fallbackContinuation = cont
            self?.fallback.speak(utterance)
        }
    }

    private static func loadConfig() -> (key: String, voiceId: String) {
        let defaultVoice = "jsCqWAovK2LkecY7zXl4" // Hana

        // 1. Config file written by VoxApp (~/.config/vox/config.json)
        let configPath = NSHomeDirectory() + "/.config/vox/config.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let key = json["elevenLabsKey"], !key.isEmpty {
            return (key, json["voiceId"] ?? defaultVoice)
        }

        // 2. Environment variable fallback
        if let key = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"], !key.isEmpty {
            return (key, defaultVoice)
        }

        // 3. ~/.claude/.env fallback
        let envPath = NSHomeDirectory() + "/.claude/.env"
        if let content = try? String(contentsOfFile: envPath, encoding: .utf8) {
            for line in content.components(separatedBy: "\n") {
                if line.hasPrefix("ELEVENLABS_API_KEY=") {
                    let key = line.dropFirst("ELEVENLABS_API_KEY=".count)
                        .trimmingCharacters(in: .init(charactersIn: "\"'\r "))
                    return (key, defaultVoice)
                }
            }
        }

        return ("", defaultVoice)
    }

    enum SynthError: Error, LocalizedError {
        case noKey
        case apiError(String)
        var errorDescription: String? {
            switch self {
            case .noKey: return "ElevenLabs API key not configured"
            case .apiError(let m): return m
            }
        }
    }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        fallbackContinuation?.resume(); fallbackContinuation = nil
    }
}

extension SpeechSynthesizer: AVAudioPlayerDelegate {
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        audioPlayerContinuation?.resume()
        audioPlayerContinuation = nil
        audioPlayer = nil
    }
}
