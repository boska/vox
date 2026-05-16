import AVFoundation
import Foundation

public class SpeechSynthesizer: NSObject {
    private let elevenLabsKey: String
    private let voiceId = "jsCqWAovK2LkecY7zXl4" // Hana
    private let model = "eleven_multilingual_v2"
    private let voiceSettings: [String: Any] = [
        "stability": 0.35,
        "similarity_boost": 0.8,
        "style": 0.5,
        "use_speaker_boost": true
    ]

    private let fallback = AVSpeechSynthesizer()
    private var fallbackContinuation: CheckedContinuation<Void, Never>?

    public override init() {
        self.elevenLabsKey = SpeechSynthesizer.loadKey()
        super.init()
        fallback.delegate = self
    }

    // 抓音頻 data（可並行呼叫）
    public func fetchAudio(_ text: String) async throws -> Data {
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
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                guard let player = try? AVAudioPlayer(data: data) else {
                    continuation.resume(); return
                }
                player.prepareToPlay()
                player.play()
                while player.isPlaying { Thread.sleep(forTimeInterval: 0.05) }
                continuation.resume()
            }
        }
    }

    // 簡單一次性 speak（fallback 用）
    public func speakFallback(_ text: String) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-TW")
        utterance.rate = 0.48
        await withCheckedContinuation { [weak self] cont in
            self?.fallbackContinuation = cont
            self?.fallback.speak(utterance)
        }
    }

    private static func loadKey() -> String {
        if let key = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"], !key.isEmpty { return key }
        let path = NSHomeDirectory() + "/.claude/.env"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("ELEVENLABS_API_KEY=") {
                return line.dropFirst("ELEVENLABS_API_KEY=".count)
                    .trimmingCharacters(in: .init(charactersIn: "\"'\r "))
            }
        }
        return ""
    }

    enum SynthError: Error, LocalizedError {
        case apiError(String)
        var errorDescription: String? {
            if case .apiError(let m) = self { return m }; return nil
        }
    }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        fallbackContinuation?.resume(); fallbackContinuation = nil
    }
}
