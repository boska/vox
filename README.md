# vox

**A native macOS MCP server that gives Claude a voice.**

Built in Swift. No Node.js. No Python. No Electron. Just a single binary.

```json
{
  "mcpServers": {
    "vox": {
      "command": "/path/to/vox"
    }
  }
}
```

Then just say: `listen` — and Claude hears you.

---

## Tools

| Tool | What it does |
|------|-------------|
| `listen` | Activates the mic, waits for you to speak, returns transcript + detected language when silence is detected |
| `speak` | Speaks text aloud — ElevenLabs TTS with automatic fallback to macOS system voice |

## Why Swift + macOS only

- **AVFoundation** — native mic capture, zero overhead
- **SFSpeechRecognizer** — Apple on-device speech recognition, works offline, 50+ languages
- **NLLanguageRecognizer** — automatic language detection per utterance
- **AVSpeechSynthesizer** — built-in TTS fallback, no API key needed
- Single ~200KB binary. Zero npm install. Zero Python venv.

## Requirements

- macOS 13+
- Microphone set as default in System Settings → Sound → Input
- Microphone + Speech Recognition permission for your terminal app
- Optional: `ELEVENLABS_API_KEY` in `~/.claude/.env` for high-quality multilingual TTS

## Install

### Option 1: Pre-built Binary (Recommended)

Download the latest code-signed binary:

```bash
curl -L https://github.com/boska/vox/releases/download/v1.1.0/vox-1.1.0-darwin-arm64 -o ~/vox && chmod +x ~/vox
```

Add to `~/.claude.json`:

```json
{
  "mcpServers": {
    "vox": {
      "command": "/Users/$(whoami)/vox"
    }
  }
}
```

Restart Claude Code. Done.

### Option 2: Build from Source

```bash
git clone https://github.com/boska/vox
cd vox
swift build -c release --product vox
```

Add to `~/.claude.json`:

```json
{
  "mcpServers": {
    "vox": {
      "command": "/path/to/vox/.build/release/vox"
    }
  }
}
```

Restart Claude Code.

## Voice

Default TTS voice is **Hana** via ElevenLabs (`eleven_multilingual_v2`). Supports Chinese, English, Czech, Vietnamese, and 20+ languages in the same voice. Without an ElevenLabs key, falls back to macOS system voice automatically.

## How it works

```
Claude Code
    ↓ JSON-RPC 2.0 over stdio
  vox binary
    ↓                        ↑
AVAudioEngine        AVSpeechSynthesizer
SFSpeechRecognizer       ElevenLabs API
NLLanguageRecognizer
```

No ports. No sockets. No daemon. Just stdin/stdout.

## Troubleshooting

**"No speech detected"** — speak within ~1s of calling listen, VAD cuts off after 0.8s silence.

**No default input device** — Mac mini has no built-in mic. Connect USB/Bluetooth mic or iPhone via Continuity Camera, set default in System Settings → Sound → Input.

**ElevenLabs silent** — add `ELEVENLABS_API_KEY=sk-...` to `~/.claude/.env`, or leave it out to use system voice.
