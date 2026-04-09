
import Foundation
import AppKit
import ApplicationServices
import OSLog

class AccessibilityManager {
    static let shared = AccessibilityManager()
    private init() {}

    // MARK: - Permission

    func checkPermission() -> Bool {
        AXIsProcessTrusted()
    }

    func requestPermission() {
        Logger.accessibility.info("Requesting accessibility permission from user")
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Main fix flow

    @MainActor
    func fixSelectedText() async {
        guard checkPermission() else {
            Logger.accessibility.warning("Accessibility not granted — prompting user")
            requestPermission()
            return
        }

        guard !AppState.shared.isProcessing else {
            Logger.clipboard.info("Already processing — ignoring duplicate trigger")
            return
        }

        Logger.clipboard.info("▶ Fix flow started")

        let pasteboard = NSPasteboard.general

        // ── Step 1: Snapshot the current clipboard so we can restore it after ──
        let snapshot = ClipboardSnapshot(from: pasteboard)
        Logger.clipboard.debug("Saved clipboard snapshot (\(snapshot.itemCount) item(s))")

        // ── Step 2: Clear clipboard then simulate ⌘C ───────────────────────────
        // ⌘C copies the active selection WITHOUT deselecting it.
        // When we later simulate ⌘V, the selection is still live, so the paste
        // REPLACES the selected text in-place — exactly what we want.
        pasteboard.clearContents()
        Logger.clipboard.debug("Clipboard cleared. Simulating ⌘C on frontmost app…")
        simulateKey(keyCode: 8, modifiers: .maskCommand) // keyCode 8 = 'c'

        // Wait for the frontmost app to write the selection to the pasteboard.
        // 200 ms is reliable across all apps tested.
        try? await Task.sleep(for: .milliseconds(200))

        guard let selectedText = pasteboard.string(forType: .string),
              !selectedText.isEmpty else {
            Logger.clipboard.warning("Clipboard still empty after ⌘C — no text was selected")
            snapshot.restore(to: pasteboard)
            return
        }

        Logger.clipboard.info("Captured \(selectedText.count) chars: \"\(selectedText.prefix(120))\"")

        // ── Step 3: Send to LLM ────────────────────────────────────────────────
        AppState.shared.isProcessing = true
        Logger.llm.info("Sending text to LLM for correction…")

        do {
            let corrected = try await LLMService.shared.correctGrammar(selectedText)

            Logger.llm.info("Correction received (\(corrected.count) chars): \"\(corrected.prefix(120))\"")

            // ── Step 4: Write corrected text to clipboard, then simulate ⌘V ────
            // At this point the original selection is STILL active (⌘C doesn't
            // deselect). ⌘V replaces the selection with the corrected text.
            pasteboard.clearContents()
            pasteboard.setString(corrected, forType: .string)
            Logger.clipboard.debug("Wrote corrected text to clipboard. Simulating ⌘V…")

            simulateKey(keyCode: 9, modifiers: .maskCommand) // keyCode 9 = 'v'

            // ── Step 5: Restore original clipboard ─────────────────────────────
            // Wait long enough for the target app to finish reading the pasteboard
            // before we swap it back. 400 ms covers slow/remote/VM apps.
            try? await Task.sleep(for: .milliseconds(400))
            snapshot.restore(to: pasteboard)
            Logger.clipboard.info("✓ Original clipboard restored. Replacement complete.")

            AppState.shared.isProcessing = false
            AppState.shared.markSuccess()

        } catch {
            Logger.llm.error("✗ LLM error: \(error.localizedDescription)")
            snapshot.restore(to: pasteboard)
            AppState.shared.isProcessing = false
            AppState.shared.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Key simulation

    private func simulateKey(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)

        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        down?.flags = modifiers
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        up?.flags = modifiers
        up?.post(tap: .cghidEventTap)
    }
}

// MARK: - Clipboard snapshot / restore

private struct ClipboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    var itemCount: Int { items.count }

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
