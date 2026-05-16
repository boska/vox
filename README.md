# vox MCP

A macOS MCP (Model Context Protocol) server that adds **voice I/O to Claude Code** — speak to Claude, Claude speaks back.

## What it does

| Tool | Description |
|------|-------------|
| `listen` | Activates the microphone and returns a transcript when silence is detected (~0.8 s) |
| `speak` | Speaks text aloud via ElevenLabs TTS (Hana voice), with automatic fallback to Mac system voice |

## Requirements

- macOS 13+
- Xcode / Swift toolchain
- Microphone connected and set as default input (System Settings → Sound → Input)
- Microphone permission granted to the terminal app (iTerm2, Terminal, etc.)
- Speech Recognition permission granted (prompted on first `listen` call)
- Optional: `ELEVENLABS_API_KEY` in `~/.claude/.env` for high-quality TTS

## Build

```bash
cd vox
swift build -c release --product vox
```

The binary lands at `.build/release/vox`.

## Install in Claude Code

Add to `~/.claude.json` under `mcpServers`:

```json
{
  "mcpServers": {
    "vox": {
      "command": "/path/to/vox/.build/release/vox"
    }
  }
}
```

Or add via Claude Code settings UI: **Settings → MCP Servers → Add**.

Restart Claude Code after adding.

## Distribute to others

### Option A — share the binary (simplest)

1. Build on your Mac: `swift build -c release --product vox`
2. Share `.build/release/vox`
3. Recipient puts the binary anywhere and adds it to their `~/.claude.json`

> Note: the binary is arm64 (Apple Silicon). For Intel Macs, the recipient must build from source.

### Option B — share via GitHub (recommended)

1. Push this repo to GitHub
2. Add a GitHub Actions workflow to build and attach the binary to releases
3. Recipients download the release binary and configure their `~/.claude.json`

### Option C — npm/npx wrapper (most discoverable)

Wrap the binary in an npm package so users can run it with `npx`:

```json
{
  "mcpServers": {
    "vox": {
      "command": "npx",
      "args": ["-y", "vox"]
    }
  }
}
```

This requires publishing to npm with the macOS binary bundled or a postinstall build step.

### Option D — MCP Registry

Submit to the [MCP Registry](https://github.com/modelcontextprotocol/servers) so it appears in Claude Code's built-in server browser.

## Architecture

```
vox/
├── Sources/
│   ├── VoiceCore/
│   │   ├── SpeechRecognizer.swift   # AVAudioEngine + SFSpeechRecognizer + VAD
│   │   └── SpeechSynthesizer.swift  # ElevenLabs TTS + Mac AVSpeechSynthesizer fallback
│   └── VoxMCP/
│       ├── main.swift               # RunLoop entry point
│       └── MCPServer.swift          # JSON-RPC 2.0 stdio MCP server
└── Package.swift
```

The server communicates over **stdio** using JSON-RPC 2.0 — the standard MCP transport. Claude Code launches it as a subprocess and pipes messages back and forth.

## Troubleshooting

**"No speech detected"** — mic is working but VAD timeout fired before speech. Speak louder or closer to the mic.

**"Microphone permission denied"** — go to System Settings → Privacy & Security → Microphone and enable your terminal app.

**No default input device** — Mac mini and some Macs have no built-in mic. Connect a USB/Bluetooth mic or iPhone (via Continuity Camera) and set it as default in System Settings → Sound → Input.

**ElevenLabs not speaking** — add `ELEVENLABS_API_KEY=your_key` to `~/.claude/.env`. Without it, the server automatically falls back to Mac system voice.
