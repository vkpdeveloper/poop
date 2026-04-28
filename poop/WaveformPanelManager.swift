
import SwiftUI
import AppKit
import Combine

// MARK: - WaveformPanelManager

/// Manages the always-on-top floating pill panel that shows the waveform animation
/// during voice recording and a spinner during transcription.
///
/// Positioned horizontally centred, 5 % up from the bottom of the main screen.
class WaveformPanelManager {
    static let shared = WaveformPanelManager()

    private var panel: NSPanel?

    private let panelSize = NSSize(width: 200, height: 52)

    private init() {}

    // MARK: - Setup

    @MainActor
    func setup() {
        guard panel == nil else { return }

        let hosting = NSHostingView(rootView: WaveformIndicatorView())
        hosting.frame = NSRect(origin: .zero, size: panelSize)

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        p.level               = .floating
        p.backgroundColor     = .clear
        p.isOpaque            = false
        p.hasShadow           = false
        p.ignoresMouseEvents  = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior  = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView         = hosting

        panel = p
        repositionPanel()
    }

    // MARK: - Show / Hide

    @MainActor
    func show() {
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
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame  = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = frame.midX - panelSize.width / 2
        let y = frame.minY + frame.height * 0.05
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - WaveformIndicatorView

/// Compact dark pill with animated waveform bars while recording, or a spinner while transcribing.
struct WaveformIndicatorView: View {
    private let state = AppState.shared

    private let barCount = 7
    private static let offsets: [Double] = [0, 0.9, 1.7, 2.5, 3.3, 4.2, 5.1]

    @State private var phase: Double = 0

    private let clock = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Dark pill background — cornerRadius = height/2 for a true pill
            Capsule()
                .fill(Color(red: 0.10, green: 0.10, blue: 0.12))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )

            if state.isTranscribing {
                transcribingContent
                    .transition(.opacity)
            } else {
                recordingContent
                    .transition(.opacity)
            }
        }
        .frame(width: 200, height: 52)
        .shadow(color: .black.opacity(0.50), radius: 18, x: 0, y: 8)
        .animation(.easeInOut(duration: 0.2), value: state.isTranscribing)
        .onReceive(clock) { _ in
            phase += 0.12
        }
    }

    // MARK: - Recording content

    private var recordingContent: some View {
        HStack(alignment: .center, spacing: 4) {
            // Red recording dot
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .opacity(0.85)

            // Waveform bars
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 3, height: barHeight(for: i))
                }
            }
            .frame(height: 30)
            .animation(.linear(duration: 0.04), value: phase)
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Transcribing content

    private var transcribingContent: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.65)
                .colorScheme(.dark)

            Text("Transcribing…")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.75))
        }
    }

    // MARK: - Bar height computation

    private func barHeight(for index: Int) -> CGFloat {
        let level  = Double(max(0.12, state.recordingLevel))
        let wave   = (sin(phase + Self.offsets[index]) + 1) / 2  // 0…1
        let minH: Double = 3
        let maxH: Double = 26
        return CGFloat(minH + (maxH - minH) * wave * level)
    }
}

