
import Foundation
import Observation

@Observable
class AppState {
    static let shared = AppState()
    private init() {}

    // MARK: - Grammar Fix State

    var isProcessing = false {
        didSet { updateIndicator() }
    }

    var isSuccess = false {
        didSet { updateIndicator() }
    }

    var errorMessage: String?

    // Stored so we can cancel before spawning a new one, preventing race conditions
    // when markSuccess() is called in rapid succession.
    private var successTask: Task<Void, Never>?

    @MainActor
    func markSuccess() {
        successTask?.cancel()
        isSuccess = true
        successTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            isSuccess = false
        }
    }

    // MARK: - Voice Dictation State

    /// True while the microphone is actively recording.
    var isRecording = false {
        didSet { updateWaveformPanel() }
    }

    /// Normalised microphone input level (0…1). Driven by a metering timer in VoiceRecorder.
    var recordingLevel: Float = 0

    /// True while the transcription subprocess is running.
    var isTranscribing = false {
        didSet { updateWaveformPanel() }
    }

    // MARK: - Floating indicator

    /// Show the floating indicator whenever processing or success, hide when idle.
    private func updateIndicator() {
        Task { @MainActor in
            if self.isProcessing || self.isSuccess {
                FloatingIndicatorManager.shared.show()
            } else {
                FloatingIndicatorManager.shared.hide()
            }
        }
    }

    /// Show the waveform panel while recording or transcribing.
    private func updateWaveformPanel() {
        Task { @MainActor in
            if self.isRecording || self.isTranscribing {
                WaveformPanelManager.shared.show()
            } else {
                WaveformPanelManager.shared.hide()
            }
        }
    }
}
