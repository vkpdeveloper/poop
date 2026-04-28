
import Foundation
import CoreGraphics
import AppKit
import ApplicationServices
import OSLog

// MARK: - Module-level cache (readable by @convention(c) callback on any thread)
//
// Grammar-fix hotkey
private nonisolated(unsafe) var _cachedKeyCode:  Int          = 3
private nonisolated(unsafe) var _cachedFlags:     CGEventFlags = [.maskCommand, .maskShift]

// Voice-dictation hotkey
private nonisolated(unsafe) var _voiceEnabled:   Bool          = false
private nonisolated(unsafe) var _voiceKeyCode:   Int           = 9    // V by default
private nonisolated(unsafe) var _voiceFlags:     CGEventFlags  = [.maskControl, .maskAlternate]

// Set by VoiceDictationManager when recording starts/stops, so the tap can
// intercept the Enter/Return key to finish dictation.
nonisolated(unsafe) var _isRecordingVoice: Bool = false

// Modifier mask used by the tap callback — must be module-level so the
// @convention(c) closure can reference it without capturing context.
private let _relevantModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

// MARK: - HotkeyManager

class HotkeyManager {
    static let shared = HotkeyManager()
    private var eventTap:      CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    // MARK: - Setup

    /// Call from main thread after accessibility is granted or settings change.
    func setup() {
        guard AXIsProcessTrusted() else {
            Logger.hotkey.warning("setup() called but accessibility not granted — skipping")
            return
        }
        teardown()

        // Sync grammar-fix hotkey
        _cachedKeyCode = SettingsManager.shared.hotkeyKeyCode
        _cachedFlags   = SettingsManager.shared.cgEventFlags

        // Sync voice-dictation hotkey
        _voiceEnabled  = SettingsManager.shared.voiceDictationEnabled
        _voiceKeyCode  = SettingsManager.shared.voiceHotkeyKeyCode
        _voiceFlags    = SettingsManager.shared.voiceCGEventFlags

        Logger.hotkey.info("Grammar hotkey: \(SettingsManager.shared.displayString)")
        Logger.hotkey.info("Voice hotkey:   \(SettingsManager.shared.voiceDisplayString)")

        // Listen for keyDown events only.
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, _ -> Unmanaged<CGEvent>? in

            guard type == .keyDown else { return Unmanaged.passRetained(event) }

            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let pressed = event.flags.intersection(_relevantModifiers)

            // ── Enter / Return while recording → stop dictation ───────────────
            // keyCode 36 = Return, 76 = numpad Enter
            if (keyCode == 36 || keyCode == 76), _isRecordingVoice {
                Task { @MainActor in
                    await VoiceDictationManager.shared.stopAndTranscribe()
                }
                return nil  // consume so target app doesn't get a newline
            }

            // ── Escape while recording → cancel dictation ─────────────────────
            // keyCode 53 = Escape
            if keyCode == 53, _isRecordingVoice {
                Task { @MainActor in
                    VoiceDictationManager.shared.cancelRecording()
                }
                return nil  // consume the Escape
            }

            // ── Grammar fix hotkey ─────────────────────────────────────────────
            if keyCode == _cachedKeyCode, pressed == _cachedFlags {
                Task { @MainActor in
                    await AccessibilityManager.shared.fixSelectedText()
                }
                return nil
            }

            // ── Voice dictation hotkey ─────────────────────────────────────────
            // _voiceKeyCode == -1 means "not configured" — never fire
            if _voiceEnabled, _voiceKeyCode != -1,
               keyCode == _voiceKeyCode, pressed == _voiceFlags {
                Task { @MainActor in
                    VoiceDictationManager.shared.toggle()
                }
                return nil
            }

            return Unmanaged.passRetained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap:              .cghidEventTap,
            place:            .headInsertEventTap,
            options:          .defaultTap,
            eventsOfInterest: eventMask,
            callback:         callback,
            userInfo:         nil
        ) else {
            Logger.hotkey.error("CGEvent.tapCreate failed — Accessibility permission likely not granted")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            Logger.hotkey.error("CFMachPortCreateRunLoopSource returned nil")
            CFMachPortInvalidate(tap)
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap      = tap
        runLoopSource = source
        Logger.hotkey.info("✓ CGEventTap active (keyDown)")
    }

    // MARK: - Reinstall

    func reinstall() { setup() }

    // MARK: - Recording state sync

    /// Called by VoiceDictationManager so the tap callback knows when to intercept Enter.
    func setRecordingState(_ recording: Bool) {
        _isRecordingVoice = recording
    }

    // MARK: - Teardown

    func teardown() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            Logger.hotkey.info("CGEventTap disabled")
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap      = nil
        runLoopSource = nil
    }
}
