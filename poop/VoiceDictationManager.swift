
import Foundation
import AppKit
import OSLog

// MARK: - VoiceDictationManager

/// Orchestrates the full voice dictation pipeline:
///   trigger → mic check → record → stop (Enter) → transcribe → clipboard → paste
///
/// All public methods are `@MainActor` so they can be called directly from the
/// hotkey callback (which dispatches to `@MainActor`).
@MainActor
class VoiceDictationManager {
    static let shared = VoiceDictationManager()
    private init() {}

    // MARK: - Public entry points

    /// Toggle recording on/off. Called by the voice hotkey.
    func toggle() {
        if AppState.shared.isRecording {
            Task { await stopAndTranscribe() }
        } else {
            Task { await startRecording() }
        }
    }

    /// Starts recording. Checks mic permission first; shows an alert if denied.
    func startRecording() async {
        guard SettingsManager.shared.voiceDictationEnabled else { return }
        guard !AppState.shared.isRecording, !AppState.shared.isTranscribing else { return }

        // Must not already be in a grammar-fix flow
        guard !AppState.shared.isProcessing else {
            Logger.voice.info("Grammar fix in progress — ignoring voice trigger")
            return
        }

        // STT environment check
        guard SpeechToTextService.shared.setupState == .ready else {
            showAlert(
                title: "Voice Dictation Not Ready",
                message: "The speech-to-text model is not set up yet. Please visit Settings → Voice Dictation and click \"Set Up\"."
            )
            return
        }

        // Microphone permission
        let granted = await VoiceRecorder.shared.requestPermission()
        guard granted else {
            showMicrophoneDeniedAlert()
            return
        }

        // Start recording
        do {
            _ = try VoiceRecorder.shared.startRecording()
            AppState.shared.isRecording = true
            HotkeyManager.shared.setRecordingState(true)
            Logger.voice.info("Dictation started")
        } catch {
            Logger.voice.error("Could not start recording: \(error.localizedDescription)")
            showAlert(
                title: "Could Not Start Recording",
                message: error.localizedDescription
            )
        }
    }

    /// Stops the active recording, transcribes the audio, and inserts the text.
    func stopAndTranscribe() async {
        guard AppState.shared.isRecording else { return }

        // Stop and grab the audio file
        guard let audioURL = VoiceRecorder.shared.stopRecording() else {
            AppState.shared.isRecording = false
            return
        }

        AppState.shared.isRecording   = false
        AppState.shared.isTranscribing = true
        HotkeyManager.shared.setRecordingState(false)
        Logger.voice.info("Recording stopped. Beginning transcription…")

        do {
            let text = try await SpeechToTextService.shared.transcribe(audioURL: audioURL)

            AppState.shared.isTranscribing = false
            Logger.voice.info("Got transcript (\(text.count) chars). Inserting…")

            guard !text.isEmpty else {
                Logger.voice.warning("Empty transcript — nothing to insert")
                showAlert(
                    title: "Nothing Transcribed",
                    message: "No speech was detected. Try speaking closer to the microphone."
                )
                return
            }

            await insertText(text)

        } catch {
            AppState.shared.isTranscribing = false
            Logger.voice.error("Transcription failed: \(error.localizedDescription)")
            showAlert(title: "Transcription Failed", message: error.localizedDescription)
        }

        // DEBUG: keep temp audio file for inspection
        // try? FileManager.default.removeItem(at: audioURL)
        Logger.voice.info("Audio file kept at: \(audioURL.path)")
    }

    /// Cancels an in-progress recording without transcribing.
    func cancelRecording() {
        guard AppState.shared.isRecording else { return }
        VoiceRecorder.shared.cancelRecording()
        AppState.shared.isRecording = false
        HotkeyManager.shared.setRecordingState(false)
        Logger.voice.info("Recording cancelled")
    }

    // MARK: - Text insertion

    /// Copies `text` to the clipboard and simulates ⌘V to paste it into the
    /// frontmost app — identical to the grammar-fix insertion approach.
    private func insertText(_ text: String) async {
        let pasteboard = NSPasteboard.general

        // Snapshot existing clipboard so we can restore it
        let snapshot = ClipboardSnapshot(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        Logger.voice.debug("Wrote transcript to clipboard. Simulating ⌘V…")
        simulateKey(keyCode: 9, modifiers: .maskCommand) // keyCode 9 = V

        // Wait for the target app to read the clipboard before we restore
        try? await Task.sleep(for: .milliseconds(400))
        snapshot.restore(to: pasteboard)
        Logger.voice.info("✓ Transcript pasted and original clipboard restored")
    }

    // MARK: - Key simulation (mirrors AccessibilityManager)

    private func simulateKey(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        down?.flags = modifiers
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        up?.flags = modifiers
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Alerts

    private func showMicrophoneDeniedAlert() {
        let alert = NSAlert()
        alert.messageText    = "Microphone Access Denied"
        alert.informativeText = "Poop needs microphone access for voice dictation.\n\nGo to System Settings → Privacy & Security → Microphone and enable Poop."
        alert.alertStyle     = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText     = title
        alert.informativeText = message
        alert.alertStyle      = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - ClipboardSnapshot (local copy mirrors AccessibilityManager's private type)

private struct ClipboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    init(from pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let rebuilt: [NSPasteboardItem] = items.map { pairs in
            let pb = NSPasteboardItem()
            for (type, data) in pairs { pb.setData(data, forType: type) }
            return pb
        }
        pasteboard.writeObjects(rebuilt)
    }
}
