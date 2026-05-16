import VoiceCore
import Foundation

enum PipelineError: Error, LocalizedError {
    case emptyTranscript
    var errorDescription: String? { "沒有偵測到語音" }
}

class VoicePipeline {
    private let stt = SpeechRecognizer()
    private let ai = GuideAI()
    private let tts = SpeechSynthesizer()

    func requestPermissions() async -> Bool {
        await SpeechRecognizer.requestAuthorization()
    }

    func listen() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            stt.onSilenceDetected = { [weak self] in
                guard let self else { return }
                let text = self.stt.stop().trimmingCharacters(in: .whitespaces)
                if text.isEmpty {
                    continuation.resume(throwing: PipelineError.emptyTranscript)
                } else {
                    continuation.resume(returning: text)
                }
            }
            do { try stt.start() } catch { continuation.resume(throwing: error) }
        }
    }

    // 串流回應：Claude token → 句子 → 並行抓音頻 → 照順序播
    func respondStreaming(to text: String) async throws {
        var audioTasks: [Task<Data?, Never>] = []

        for try await sentence in ai.chatStream(text) {
            // 立刻開始抓這句的音頻（不等）
            let task = Task { [weak self] in
                try? await self?.tts.fetchAudio(sentence)
            }
            audioTasks.append(task)
        }

        // 照順序播，每個 task 在抓音頻時已並行跑了
        for task in audioTasks {
            if let data = await task.value {
                await tts.playData(data)
            }
        }
    }

    func cancelListening() { _ = stt.stop() }
    func resetHistory() { ai.reset() }
}
