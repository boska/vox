import SwiftUI
import AVFoundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case apiKey = "API Key"
    case voice  = "Voice"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .apiKey: return "key.fill"
        case .voice:  return "waveform"
        }
    }
}

struct SettingsView: View {
    @State private var selection: SettingsSection? = .apiKey

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(150)
        } detail: {
            switch selection {
            case .apiKey: APIKeyDetailView()
            case .voice:  VoiceDetailView()
            case nil:     Text("Select a section").foregroundStyle(.secondary)
            }
        }
        .frame(width: 580, height: 360)
    }
}

// MARK: - API Key

struct APIKeyDetailView: View {
    @State private var config = VoxConfig.load()
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                SecureField("ElevenLabs API Key", text: $config.elevenLabsKey)
                    .textContentType(.password)
            } header: {
                Text("ElevenLabs")
            } footer: {
                Text("Your key is stored locally in ~/.config/vox/config.json")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                if saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .padding()
        }
    }

    private func save() {
        config.save()
        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { saved = false }
        }
    }
}

// MARK: - Voice

struct VoiceDetailView: View {
    @State private var config = VoxConfig.load()
    @State private var voices: [ElevenVoice] = []
    @State private var selectedVoiceId: String = ""
    @State private var isFetching = false
    @State private var fetchError: String? = nil
    @State private var saved = false
    @State private var playingVoiceId: String? = nil
    @State private var audioPlayer: AVAudioPlayer? = nil

    var body: some View {
        VStack(spacing: 0) {
            if voices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No voices loaded")
                        .foregroundStyle(.secondary)
                    if let err = fetchError {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                    Button(isFetching ? "Fetching…" : "Fetch Voices") {
                        Task { await fetchVoices() }
                    }
                    .disabled(config.elevenLabsKey.isEmpty || isFetching)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(voices, selection: $selectedVoiceId) { voice in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(voice.name).fontWeight(selectedVoiceId == voice.voice_id ? .semibold : .regular)
                        }
                        Spacer()
                        Button {
                            Task { await preview(voice: voice) }
                        } label: {
                            Image(systemName: playingVoiceId == voice.voice_id ? "stop.fill" : "play.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .tag(voice.voice_id)
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Button(isFetching ? "Fetching…" : "Refresh") {
                    Task { await fetchVoices() }
                }
                .disabled(config.elevenLabsKey.isEmpty || isFetching)

                Spacer()

                if saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .disabled(selectedVoiceId.isEmpty)
            }
            .padding()
        }
        .onAppear {
            selectedVoiceId = config.voiceId
            if !config.elevenLabsKey.isEmpty { Task { await fetchVoices() } }
        }
    }

    private func fetchVoices() async {
        isFetching = true
        fetchError = nil
        do {
            voices = try await ElevenLabsAPI.fetchVoices(apiKey: config.elevenLabsKey)
            if selectedVoiceId.isEmpty { selectedVoiceId = voices.first?.voice_id ?? "" }
        } catch {
            fetchError = error.localizedDescription
        }
        isFetching = false
    }

    private func preview(voice: ElevenVoice) async {
        guard !config.elevenLabsKey.isEmpty else { return }
        playingVoiceId = voice.voice_id
        defer { playingVoiceId = nil }
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice.voice_id)")!)
        req.httpMethod = "POST"
        req.setValue(config.elevenLabsKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "text": "Hello, this is \(voice.name). How can I help you today?",
            "model_id": "eleven_multilingual_v2"
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return }
        await MainActor.run {
            audioPlayer = try? AVAudioPlayer(data: data)
            audioPlayer?.play()
        }
    }

    private func save() {
        config.voiceId = selectedVoiceId
        config.voiceName = voices.first(where: { $0.voice_id == selectedVoiceId })?.name ?? config.voiceName
        config.save()
        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { saved = false }
        }
    }
}
