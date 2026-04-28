
import Foundation
import AVFoundation
import OSLog

// MARK: - VoiceRecorder

/// Records microphone audio to a temporary WAV file and meters the input level
/// for driving the waveform animation.
///
/// Designed to be used from the main actor (VoiceDictationManager). All mutations
/// of AppState happen on the main actor via `Task { @MainActor in … }`.
class VoiceRecorder: NSObject {
    static let shared = VoiceRecorder()

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var currentFileURL: URL?

    // Parakeet expects 16 kHz mono 16-bit PCM.
    private let recordingSettings: [String: Any] = [
        AVFormatIDKey:            Int(kAudioFormatLinearPCM),
        AVSampleRateKey:          16_000.0,
        AVNumberOfChannelsKey:    1,
        AVLinearPCMBitDepthKey:   16,
        AVLinearPCMIsFloatKey:    false,
        AVLinearPCMIsBigEndianKey: false,
    ]

    private override init() {}

    // MARK: - Permission

    /// Returns true when microphone access is already granted or newly granted.
    /// Returns false when the user denied or when the hardware is unavailable.
    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    // MARK: - Start

    /// Starts recording into a new temporary WAV file and returns its URL.
    /// Throws if recording cannot start (e.g., missing permission, hardware issue).
    func startRecording() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("poop_dictation_\(UUID().uuidString).wav")

        let r = try AVAudioRecorder(url: tmp, settings: recordingSettings)
        r.delegate = self
        r.isMeteringEnabled = true
        guard r.record() else {
            throw VoiceRecorderError.recordingFailedToStart
        }

        recorder = r
        currentFileURL = tmp

        // Drive level metering at ~20 Hz
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateLevel()
        }

        Logger.voice.info("▶ Recording started → \(tmp.lastPathComponent)")
        return tmp
    }

    // MARK: - Stop

    /// Stops recording and returns the URL of the audio file (or nil if not recording).
    @discardableResult
    func stopRecording() -> URL? {
        recorder?.stop()
        stopMetering()
        let url = currentFileURL
        recorder = nil
        currentFileURL = nil

        if let url {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size  = (attrs?[.size] as? Int) ?? 0
            Logger.voice.info("■ Recording stopped — file size: \(size) bytes at \(url.path)")
        } else {
            Logger.voice.info("■ Recording stopped — no file URL")
        }
        return url
    }

    /// Stops and deletes the in-progress recording (e.g., on cancel or error).
    func cancelRecording() {
        recorder?.stop()
        recorder = nil
        stopMetering()
        if let url = currentFileURL {
            try? FileManager.default.removeItem(at: url)
            Logger.voice.info("✗ Recording cancelled and temp file removed")
        }
        currentFileURL = nil
        Task { @MainActor in
            AppState.shared.recordingLevel = 0
        }
    }

    // MARK: - Private

    private func updateLevel() {
        guard let r = recorder, r.isRecording else { return }
        r.updateMeters()
        // averagePower is in dB (−160…0). Map to 0…1 for the waveform.
        let dB = r.averagePower(forChannel: 0)
        let minDB: Float = -50
        let clamped = max(minDB, dB)
        let normalized = (clamped - minDB) / (-minDB)  // 0…1
        Task { @MainActor in
            AppState.shared.recordingLevel = normalized
        }
    }

    private func stopMetering() {
        levelTimer?.invalidate()
        levelTimer = nil
        Task { @MainActor in
            AppState.shared.recordingLevel = 0
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension VoiceRecorder: AVAudioRecorderDelegate {
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let e = error {
            Logger.voice.error("AVAudioRecorder encode error: \(e.localizedDescription)")
        }
        stopMetering()
    }
}

// MARK: - Errors

enum VoiceRecorderError: LocalizedError {
    case recordingFailedToStart

    var errorDescription: String? {
        switch self {
        case .recordingFailedToStart:
            return "The microphone could not be started. Please check your microphone is connected and not in use by another app."
        }
    }
}
