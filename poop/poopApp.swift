
import SwiftUI
import AppKit
import OSLog

@main
struct PoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar icon + dropdown — this is the entire visible UI of the app.
        MenuBarExtra {
            MenuContentView()
        } label: {
            MenuBarLabel()
        }

        // Settings window, opened via ⌘, or the menu
        Settings {
            SettingsView()
        }
    }
}

// MARK: - Menu Bar Label (with blink when processing)

struct MenuBarLabel: View {
    @State private var blinkOpacity: Double = 1.0

    var body: some View {
        let state = AppState.shared
        Group {
            if state.isSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if state.isProcessing {
                Image(systemName: "ellipsis.circle")
                    .opacity(blinkOpacity)
            } else {
                Image(systemName: "sparkles")
            }
        }
        .onChange(of: state.isProcessing) { _, processing in
            if processing {
                blinkOpacity = 1.0
                withAnimation(
                    .easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true)
                ) {
                    blinkOpacity = 0.15
                }
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    blinkOpacity = 1.0
                }
            }
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var accessibilityTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.app.info("Poop launched")
        // Hide from Dock — we are a pure menu bar utility
        NSApp.setActivationPolicy(.accessory)
        // Create the floating indicator panel (hidden until first use)
        FloatingIndicatorManager.shared.setup()
        // Create the waveform panel for voice dictation (hidden until recording)
        WaveformPanelManager.shared.setup()
        // Check if the STT environment is already configured
        SpeechToTextService.shared.checkReadiness()
        setupHotkey()
    }

    private func setupHotkey() {
        if AccessibilityManager.shared.checkPermission() {
            Logger.app.info("Accessibility granted — setting up hotkey immediately")
            HotkeyManager.shared.setup()
        } else {
            Logger.app.warning("Accessibility not granted — prompting and polling every 2 s")
            AccessibilityManager.shared.requestPermission()
            accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                if AccessibilityManager.shared.checkPermission() {
                    Logger.app.info("Accessibility now granted — setting up hotkey")
                    HotkeyManager.shared.setup()
                    timer.invalidate()
                    self?.accessibilityTimer = nil
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.app.info("Poop terminating — tearing down hotkey")
        HotkeyManager.shared.teardown()
        accessibilityTimer?.invalidate()
    }
}
