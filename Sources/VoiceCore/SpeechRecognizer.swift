import Speech
import AVFoundation

public enum SpeechRecognizerError: Error, LocalizedError {
    case microphonePermissionDenied
    case speechPermissionDenied
    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied: return "Microphone permission denied — grant access in System Settings > Privacy > Microphone"
        case .speechPermissionDenied: return "Speech recognition permission denied — grant access in System Settings > Privacy > Speech Recognition"
        }
    }
}

public class SpeechRecognizer {
    private var recognizer: SFSpeechRecognizer
    private var audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    public private(set) var transcript = ""

    // VAD state
    private var hasSpeech = false
    private var lastSpeechDate = Date.distantPast
    private var silenceTimer: DispatchSourceTimer?
    private let silenceThresholdDB: Float = -45.0
    private let silenceDuration: TimeInterval = 0.8

    public var onSilenceDetected: (() -> Void)?

    public init(locale: String = "zh-TW") {
        if let r = SFSpeechRecognizer(locale: Locale(identifier: locale)), r.isAvailable {
            recognizer = r
        } else {
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
        }
    }

    public static func requestAuthorization() async -> Bool {
        // Request microphone permission first
        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        guard micGranted else { return false }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public func start() throws {
        // Check mic permission — installTap throws an uncatchable ObjC NSException if denied
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw SpeechRecognizerError.microphonePermissionDenied
        }
        transcript = ""
        hasSpeech = false
        lastSpeechDate = Date.distantPast

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result { self.transcript = result.bestTranscription.formattedString }
        }

        // Install tap with nil format first (connects inputNode to the graph),
        // then prepare (requires at least one connected node), then start.
        // nil lets AVAudio pick the hardware format — avoids deinterleaved mismatch.
        let inputNode = audioEngine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            self.request?.append(buffer)
            self.checkVAD(buffer: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    @discardableResult
    public func stop() -> String {
        silenceTimer?.cancel()
        silenceTimer = nil

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil

        return transcript
    }

    private func checkVAD(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sum: Float = 0
        for i in 0..<frameLength { sum += channelData[i] * channelData[i] }
        let rms = sqrt(sum / Float(frameLength))
        let db = rms > 0 ? 20 * log10(rms) : -160

        if db > silenceThresholdDB {
            hasSpeech = true
            lastSpeechDate = Date()
            silenceTimer?.cancel()
            silenceTimer = nil
        } else if hasSpeech {
            if silenceTimer == nil {
                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now() + silenceDuration)
                timer.setEventHandler { [weak self] in
                    self?.onSilenceDetected?()
                }
                timer.resume()
                silenceTimer = timer
            }
        }
    }
}
