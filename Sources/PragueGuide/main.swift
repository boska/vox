import Foundation

func asyncReadLine() async -> String {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: readLine() ?? "")
        }
    }
}

let pipeline = VoicePipeline()

Task {
    print("""

    ╔═══════════════════════════════════╗
    ║  🇨🇿  布拉格語音導遊  v0.1 alfa  ║
    ║     布拉格哈門教會神父 AI 版      ║
    ╚═══════════════════════════════════╝

    """)

    guard await pipeline.requestPermissions() else {
        print("❌ 需要語音辨識權限，請在系統設定中允許。")
        exit(1)
    }

    print("✅ 就緒。Return 開始 → 說話 → 靜默 1.5 秒後自動送出\n")

    while true {
        print("── 待機 ── (Return 開始 / r 重置對話)")
        let cmd = await asyncReadLine()

        if cmd.lowercased() == "r" {
            pipeline.resetHistory()
            print("🔄 對話已重置\n")
            continue
        }

        print("🎤 說吧... (靜默後自動送出)")

        do {
            let transcript = try await pipeline.listen()
            print("⏳ 神父：", terminator: "")
            try await pipeline.respondStreaming(to: transcript)
            print()
        } catch PipelineError.emptyTranscript {
            print("（沒聽到，再試一次）\n")
        } catch {
            print("❌ \(error.localizedDescription)\n")
        }
    }
}

RunLoop.main.run()
