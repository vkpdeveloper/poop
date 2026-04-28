
import SwiftUI
import AppKit

struct MenuContentView: View {
    @Environment(\.openSettings) private var openSettings
    private let state    = AppState.shared
    private let settings = SettingsManager.shared

    var body: some View {
        // Fix Grammar
        Button {
            Task { await AccessibilityManager.shared.fixSelectedText() }
        } label: {
            if state.isProcessing {
                Label("Fixing…", systemImage: "ellipsis.circle")
            } else {
                Label("Fix Grammar  \(settings.displayString)", systemImage: "sparkles")
            }
        }
        .disabled(state.isProcessing || state.isRecording || state.isTranscribing)

        // Voice Dictation
        if settings.voiceDictationEnabled {
            Button {
                Task { @MainActor in
                    if state.isRecording {
                        await VoiceDictationManager.shared.stopAndTranscribe()
                    } else {
                        await VoiceDictationManager.shared.startRecording()
                    }
                }
            } label: {
                if state.isRecording {
                    Label("Stop Dictation  ↵", systemImage: "stop.circle.fill")
                } else if state.isTranscribing {
                    Label("Transcribing…", systemImage: "ellipsis.circle")
                } else {
                    Label("Dictate  \(settings.voiceDisplayString)", systemImage: "mic.fill")
                }
            }
            .disabled(state.isProcessing || state.isTranscribing)
        }

        Divider()

        // Error banner (only shown when there's a recent error)
        if let err = state.errorMessage {
            Button {
                AppState.shared.errorMessage = nil
            } label: {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            .buttonStyle(.plain)

            Divider()
        }

        Button("Settings…") {
            openSettings()
            NSApp.activate()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Poop") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
