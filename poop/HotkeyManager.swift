
import Foundation
import CoreGraphics
import AppKit
import ApplicationServices
import OSLog

// nonisolated(unsafe) because these are accessed from a @convention(c)
// CGEventTap callback that runs on a background thread.
// They are only written from the main thread (setup/reinstall).
private nonisolated(unsafe) var _cachedKeyCode: Int = 3
private nonisolated(unsafe) var _cachedFlags: CGEventFlags = [.maskCommand, .maskShift]

class HotkeyManager {
    static let shared = HotkeyManager()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    // Call from main thread after accessibility is granted or settings change.
    func setup() {
        guard AXIsProcessTrusted() else {
            Logger.hotkey.warning("setup() called but accessibility not granted — skipping")
            return
        }
        teardown()

        // Cache hotkey config so the C callback can read it without main-actor access
        _cachedKeyCode = SettingsManager.shared.hotkeyKeyCode
        _cachedFlags   = SettingsManager.shared.cgEventFlags

        Logger.hotkey.info("Registering hotkey: \(SettingsManager.shared.displayString) (keyCode=\(_cachedKeyCode))")

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        // @convention(c): no captures allowed — uses module-level cached vars
        let callback: CGEventTapCallBack = { _, type, event, _ -> Unmanaged<CGEvent>? in
            guard type == .keyDown else {
                return Unmanaged.passRetained(event)
            }

            let keyCode  = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let relevant: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            let pressed  = event.flags.intersection(relevant)

            guard keyCode == _cachedKeyCode, pressed == _cachedFlags else {
                return Unmanaged.passRetained(event)
            }

            // Hotkey matched — dispatch to main actor and consume the event
            Task { @MainActor in
                await AccessibilityManager.shared.fixSelectedText()
            }

            return nil // consume — don't pass through to the frontmost app
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: nil
        ) else {
            Logger.hotkey.error("CGEvent.tapCreate failed — Accessibility permission likely not granted")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            Logger.hotkey.error("CFMachPortCreateRunLoopSource returned nil — hotkey will not fire")
            CFMachPortInvalidate(tap)
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap      = tap
        runLoopSource = source
        Logger.hotkey.info("✓ CGEventTap active")
    }

    // Re-register with updated hotkey settings
    func reinstall() {
        setup()
    }

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
