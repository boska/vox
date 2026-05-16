import Foundation

class GuideAI {
    private let apiKey: String
    private let model = "claude-sonnet-4-6"
    private var history: [[String: String]] = []

    private let systemPrompt = """
    你是布拉格哈門教會的神父，台灣人，在布拉格住了十幾年的在地人。
    現在你是遊客的私人即時語音導遊。

    風格規則：
    - 幽默、有神父的莊重感、偶爾犀利但不失溫度
    - 繁體中文，口語化，像在跟朋友說話
    - 每次回應嚴格不超過 80 字，因為遊客在走路邊聽
    - 可以分享真實的布拉格故事、歷史、在地小知識
    - 如果遊客問路或問景點，給簡短實用的回答
    """

    init() {
        self.apiKey = GuideAI.loadApiKey()
    }

    // 串流句子 — 每偵測到句尾就 yield 一次
    func chatStream(_ text: String) -> AsyncThrowingStream<String, Error> {
        history.append(["role": "user", "content": text])
        var fullResponse = ""

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    req.httpMethod = "POST"
                    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    req.setValue("application/json", forHTTPHeaderField: "content-type")

                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": 200,
                        "stream": true,
                        "system": systemPrompt,
                        "messages": history
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw GuideError.invalidResponse
                    }

                    var lineBuffer = ""
                    var sentenceBuffer = ""

                    for try await byte in bytes {
                        let char = Character(UnicodeScalar(byte))
                        if char == "\n" {
                            let line = lineBuffer
                            lineBuffer = ""
                            guard line.hasPrefix("data: ") else { continue }
                            let jsonStr = String(line.dropFirst(6))
                            guard jsonStr != "[DONE]" else { break }
                            guard let data = jsonStr.data(using: .utf8),
                                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                            else { continue }

                            if obj["type"] as? String == "message_stop" { break }

                            if let delta = obj["delta"] as? [String: Any],
                               delta["type"] as? String == "text_delta",
                               let token = delta["text"] as? String {
                                sentenceBuffer += token
                                fullResponse += token
                                print(token, terminator: "")
                                fflush(stdout)
                                if let sentence = GuideAI.extractSentence(&sentenceBuffer) {
                                    continuation.yield(sentence)
                                }
                            }
                        } else {
                            lineBuffer.append(char)
                        }
                    }

                    // 剩餘文字
                    let tail = sentenceBuffer.trimmingCharacters(in: .whitespaces)
                    if !tail.isEmpty { continuation.yield(tail) }

                    history.append(["role": "assistant", "content": fullResponse])
                    print()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func reset() { history = [] }

    private static func extractSentence(_ buffer: inout String) -> String? {
        let endings: [Character] = ["。", "？", "！", ".", "?", "!"]
        for (i, char) in buffer.enumerated() {
            if endings.contains(char) {
                let idx = buffer.index(buffer.startIndex, offsetBy: i + 1)
                let sentence = String(buffer[..<idx]).trimmingCharacters(in: .whitespaces)
                buffer = String(buffer[idx...]).trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty { return sentence }
            }
        }
        return nil
    }

    private static func loadApiKey() -> String {
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty { return key }
        let path = NSHomeDirectory() + "/.claude/.env"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("ANTHROPIC_API_KEY=") {
                return line.dropFirst("ANTHROPIC_API_KEY=".count)
                    .trimmingCharacters(in: .init(charactersIn: "\"'\r "))
            }
        }
        return ""
    }

    enum GuideError: Error, LocalizedError {
        case invalidResponse
        var errorDescription: String? { "API 回應異常" }
    }
}
