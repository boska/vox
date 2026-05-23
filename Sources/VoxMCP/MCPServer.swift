import Foundation
import NaturalLanguage
import VoiceCore

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
class MCPServer {
    private let stt = SpeechRecognizer()
    private let tts = SpeechSynthesizer()

    func run() async {
        let authorized = await SpeechRecognizer.requestAuthorization()
        if !authorized {
            fputs("[vox] WARNING: Microphone or speech recognition permission denied. 'listen' tool will return an error.\n", stderr)
        }

        for await line in stdinLines() {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let req = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            // Notifications have no id and need no response
            guard req["id"] != nil else { continue }

            let response = await handle(req)
            if let bytes = try? JSONSerialization.data(withJSONObject: response),
               let str = String(data: bytes, encoding: .utf8) {
                print(str)
                fflush(stdout)
            }
        }
    }

    private func stdinLines() -> AsyncStream<String> {
        AsyncStream { continuation in
            DispatchQueue.global(qos: .background).async {
                while let line = readLine() { continuation.yield(line) }
                continuation.finish()
            }
        }
    }

    private func handle(_ req: [String: Any]) async -> [String: Any] {
        let id = req["id"]!
        let method = req["method"] as? String ?? ""

        switch method {
        case "initialize":
            return rpc(id, result: [
                "protocolVersion": "2025-03-26",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "vox", "version": "1.0.0"]
            ])

        case "tools/list":
            return rpc(id, result: ["tools": toolDefinitions()])

        case "tools/call":
            let params = req["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let text = try await callTool(name: name, args: args)
                return rpc(id, result: ["content": [["type": "text", "text": text]]])
            } catch {
                return rpcError(id, code: -32000, message: error.localizedDescription)
            }

        default:
            return rpcError(id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func callTool(name: String, args: [String: Any]) async throws -> String {
        switch name {
        case "listen":
            let timeoutSeconds = (args["timeout_seconds"] as? NSNumber)?.doubleValue ?? 30.0
            writeStatus("listening")
            writeStderr("🎤 Listening... (speak now)")
            defer { writeStatus("idle") }

            let startTime = Date()
            let transcript: String = try await withTimeout(seconds: timeoutSeconds) { [weak self] in
                guard let self else { throw VoiceError.emptyTranscript }
                return try await withCheckedThrowingContinuation { continuation in
                    let once = OnceFlag()
                    self.stt.onSilenceDetected = { [weak self] in
                        guard once.tryFire() else { return }
                        guard let self else {
                            continuation.resume(throwing: VoiceError.emptyTranscript)
                            return
                        }
                        let text = self.stt.stop().trimmingCharacters(in: .whitespaces)
                        if text.isEmpty {
                            continuation.resume(throwing: VoiceError.emptyTranscript)
                        } else {
                            continuation.resume(returning: text)
                        }
                    }
                    do {
                        try self.stt.start()
                    } catch {
                        if once.tryFire() { continuation.resume(throwing: error) }
                    }
                }
            }
            let lang = detectLanguage(transcript)
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)

            writeStderr("✓ Transcript: \"\(transcript)\"")
            writeStderr("✓ Language: \(lang) | Duration: \(duration)ms")

            return formatJSON([
                "transcript": transcript,
                "language": lang,
                "duration_ms": duration
            ])

        case "speak":
            guard let text = args["text"] as? String, !text.isEmpty else {
                throw VoiceError.missingArg("text")
            }
            writeStatus("speaking")
            writeStderr("🔊 Speaking... (\(text.prefix(50))\(text.count > 50 ? "..." : ""))")
            defer { writeStatus("idle") }

            let startTime = Date()
            let sentences = splitSentences(text)
            let tasks: [Task<Data?, Never>] = sentences.map { s in
                Task { [weak self] in try? await self?.tts.fetchAudio(s) }
            }
            var anyPlayed = false
            for task in tasks {
                if let data = await task.value {
                    await tts.playData(data)
                    anyPlayed = true
                }
            }
            // Fallback to Mac system TTS if ElevenLabs failed (no key or API error)
            if !anyPlayed { await tts.speakFallback(text) }

            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            writeStderr("✓ Done | Duration: \(duration)ms")

            return formatJSON([
                "status": "spoken",
                "duration_ms": duration,
                "sentences": sentences.count,
                "fallback_used": !anyPlayed
            ])

        default:
            throw VoiceError.unknownTool(name)
        }
    }

    private func writeStderr(_ message: String) {
        fputs("\(message)\n", stderr)
        fflush(stderr)
    }

    private func formatJSON(_ dict: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    private func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        let once = OnceFlag()
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let task = Task {
                do {
                    let value = try await operation()
                    if once.tryFire() { continuation.resume(returning: value) }
                } catch {
                    if once.tryFire() { continuation.resume(throwing: error) }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                if once.tryFire() {
                    task.cancel()
                    continuation.resume(throwing: VoiceError.timeout)
                }
            }
        }
        return result
    }

    private func detectLanguage(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "und"
    }

    private func splitSentences(_ text: String) -> [String] {
        var result: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        let range = text.startIndex..<text.endIndex
        tokenizer.enumerateTokens(in: range) { tokenRange, _ in
            let sentence = String(text[tokenRange]).trimmingCharacters(in: .whitespaces)
            if !sentence.isEmpty { result.append(sentence) }
            return true
        }
        return result
    }

    private func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "listen",
                "description": "Activate microphone and listen for speech. Returns transcript when silence is detected (~0.8s) or timeout is reached. Use this when you want to hear what the user is saying.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "timeout_seconds": ["type": "number", "description": "Maximum seconds to listen before timeout (default 30)"]
                    ] as [String: Any],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "speak",
                "description": "Speak text aloud via ElevenLabs TTS (Hana voice, multilingual). Falls back to macOS system TTS if ElevenLabs is unavailable. Use this to respond verbally to the user.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "Text to speak aloud"],
                        "language": ["type": "string", "description": "BCP-47 language code (e.g. 'zh-TW', 'en-US', 'cs-CZ'). Uses detected language if not specified."]
                    ] as [String: Any],
                    "required": ["text"]
                ]
            ]
        ]
    }

    private func writeStatus(_ status: String) {
        try? status.write(toFile: "/tmp/vox-status", atomically: true, encoding: .utf8)
    }

    private func rpc(_ id: Any, result: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func rpcError(_ id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }
}

final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func tryFire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

enum VoiceError: Error, LocalizedError {
    case emptyTranscript
    case missingArg(String)
    case unknownTool(String)
    case timeout
    var errorDescription: String? {
        switch self {
        case .emptyTranscript: return "No speech detected"
        case .missingArg(let a): return "Missing argument: \(a)"
        case .unknownTool(let t): return "Unknown tool: \(t)"
        case .timeout: return "Listen timed out after the specified duration"
        }
    }
}
