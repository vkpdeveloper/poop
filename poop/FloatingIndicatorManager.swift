
import SwiftUI
import AppKit

// MARK: - Floating Indicator Manager

/// Manages a tiny always-on-top NSPanel shown at the bottom-right corner of the
/// screen while the LLM call is running. Completely non-interactive and invisible
/// when idle, so it never gets in the user's way.
class FloatingIndicatorManager {
    static let shared = FloatingIndicatorManager()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingIndicatorView>?

    private init() {}

    // MARK: - Setup

    /// Call once at app launch to create the (initially hidden) panel.
    @MainActor
    func setup() {
        guard panel == nil else { return }

        let indicatorView = FloatingIndicatorView()
        let hosting = NSHostingView(rootView: indicatorView)
        hosting.frame = NSRect(x: 0, y: 0, width: 52, height: 52)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 52, height: 52),
            styleMask: [.nonactivatingPanel, .borderless],
            backing:   .buffered,
            defer:     false
        )
        p.level                 = .floating
        p.backgroundColor       = .clear
        p.isOpaque              = false
        p.hasShadow             = false
        p.ignoresMouseEvents    = true
        p.isReleasedWhenClosed  = false
        // Stick to all spaces / full-screen apps, never grab focus cycle
        p.collectionBehavior    = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView           = hosting

        self.panel       = p
        self.hostingView = hosting
        repositionPanel()
    }

    // MARK: - Show / Hide

    @MainActor
    func show() {
        guard SettingsManager.shared.showFloatingIndicator else { return }
        repositionPanel()
        panel?.orderFrontRegardless()
    }

    @MainActor
    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Private

    @MainActor
    private func repositionPanel() {
        guard let panel else { return }
        let screen        = NSScreen.main ?? NSScreen.screens.first
        let frame         = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 22
        let x = frame.maxX - panel.frame.width  - margin
        let y = frame.minY + margin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Floating Indicator View

/// The tiny SwiftUI view rendered inside the floating panel.
/// Shows a pulsing accent-coloured dot while processing, a green checkmark
/// on success, and is empty (transparent) otherwise.
struct FloatingIndicatorView: View {
    private let state = AppState.shared

    @State private var ringScale:   CGFloat = 1.0
    @State private var ringOpacity: Double  = 0.6

    var body: some View {
        ZStack {
            if state.isSuccess {
                successDot
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else if state.isProcessing {
                processingDot
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: 52, height: 52)
        .animation(.spring(duration: 0.25), value: state.isProcessing)
        .animation(.spring(duration: 0.25), value: state.isSuccess)
    }

    // MARK: Dot states

    private var processingDot: some View {
        ZStack {
            // Expanding ring
            Circle()
                .fill(Color.accentColor.opacity(ringOpacity))
                .scaleEffect(ringScale)

            // Solid inner dot
            Circle()
                .fill(Color.accentColor)
                .frame(width: 12, height: 12)
                .shadow(color: Color.accentColor.opacity(0.5), radius: 4, x: 0, y: 0)
        }
        .frame(width: 28, height: 28)
        .padding(12)
        .background(
            Circle()
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.88))
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
        )
        .onAppear {
            ringScale   = 1.0
            ringOpacity = 0.6
            withAnimation(
                .easeInOut(duration: 0.75)
                .repeatForever(autoreverses: true)
            ) {
                ringScale   = 1.9
                ringOpacity = 0
            }
        }
        .onDisappear {
            ringScale   = 1.0
            ringOpacity = 0.6
        }
    }

    private var successDot: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.green)
            .frame(width: 28, height: 28)
            .padding(12)
            .background(
                Circle()
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.88))
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
            )
    }
}
