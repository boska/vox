import Foundation
import NaturalLanguage
import VoiceCore

class MCPServer {
    private let stt = SpeechRecognizer()
    private let tts = SpeechSynthesizer()

    func run() async {
        let authorized = await SpeechRecognizer.requestAuthorization()
        if !authorized {
            fputs("[prague-voice] WARNING: Microphone or speech recognition permission denied. 'listen' tool will return an error.\n", stderr)
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
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "vox", "version": "0.1"]
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
            let transcript: String = try await withCheckedThrowingContinuation { continuation in
                stt.onSilenceDetected = { [weak self] in
                    guard let self else { return }
                    let text = self.stt.stop().trimmingCharacters(in: .whitespaces)
                    if text.isEmpty {
                        continuation.resume(throwing: VoiceError.emptyTranscript)
                    } else {
                        continuation.resume(returning: text)
                    }
                }
                do { try stt.start() } catch { continuation.resume(throwing: error) }
            }
            let lang = detectLanguage(transcript)
            return "[\(lang)] \(transcript)"

        case "speak":
            guard let text = args["text"] as? String, !text.isEmpty else {
                throw VoiceError.missingArg("text")
            }
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
            return "spoken"

        default:
            throw VoiceError.unknownTool(name)
        }
    }

    private func detectLanguage(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "und"
    }

    private func splitSentences(_ text: String) -> [String] {
        var result: [String] = []
        var buf = ""
        let endings: [Character] = ["。", "？", "！", ".", "?", "!"]
        for ch in text {
            buf.append(ch)
            if endings.contains(ch) {
                let s = buf.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { result.append(s) }
                buf = ""
            }
        }
        let tail = buf.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    private func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "listen",
                "description": "Activate microphone and listen for speech. Returns transcript when silence is detected (~0.8s). Use this when you want to hear what the user is saying.",
                "inputSchema": ["type": "object", "properties": [:] as [String: Any], "required": [] as [String]]
            ],
            [
                "name": "speak",
                "description": "Speak text aloud via ElevenLabs TTS (Hana voice, multilingual). Use this to respond verbally to the user.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["text": ["type": "string", "description": "Text to speak aloud"]],
                    "required": ["text"]
                ]
            ]
        ]
    }

    private func rpc(_ id: Any, result: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func rpcError(_ id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }
}

enum VoiceError: Error, LocalizedError {
    case emptyTranscript
    case missingArg(String)
    case unknownTool(String)
    var errorDescription: String? {
        switch self {
        case .emptyTranscript: return "No speech detected"
        case .missingArg(let a): return "Missing argument: \(a)"
        case .unknownTool(let t): return "Unknown tool: \(t)"
        }
    }
}
