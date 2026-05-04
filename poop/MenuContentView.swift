
import SwiftUI
import AppKit

struct MenuContentView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    private let state = AppState.shared
    private let settings = SettingsManager.shared
    private let auth = KiteAuthManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Main Actions
            VStack(spacing: 4) {
                MenuActionButton(
                    icon: "sparkles",
                    iconColor: Color.accentColor,
                    title: state.isProcessing ? "Fixing…" : "Fix Grammar",
                    subtitle: settings.displayString,
                    isLoading: state.isProcessing
                ) {
                    dismiss()
                    Task { await AccessibilityManager.shared.fixSelectedText() }
                }
                .disabled(state.isProcessing || state.isRecording || state.isTranscribing)

                if settings.voiceDictationEnabled {
                    MenuActionButton(
                        icon: state.isRecording ? "stop.circle.fill" : "mic.fill",
                        iconColor: state.isRecording ? .red : .orange,
                        title: state.isRecording ? "Stop Dictation" : state.isTranscribing ? "Transcribing…" : "Voice Dictate",
                        subtitle: state.isRecording ? "Press ↵ to finish" : settings.voiceDisplayString,
                        isLoading: state.isTranscribing
                    ) {
                        dismiss()
                        Task { @MainActor in
                            if state.isRecording {
                                await VoiceDictationManager.shared.stopAndTranscribe()
                            } else {
                                await VoiceDictationManager.shared.startRecording()
                            }
                        }
                    }
                    .disabled(state.isProcessing || state.isTranscribing)
                }
            }
            .padding(12)

            Divider()
                .padding(.horizontal, 12)

            // Portfolio (if connected)
            if !settings.kiteAccessToken.isEmpty {
                ModernPortfolioView()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Divider()
                    .padding(.horizontal, 12)
            }

            // Error Banner
            if let err = state.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 14))
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        AppState.shared.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.red.opacity(0.06))
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
                    .padding(.horizontal, 12)
            }

            // Footer Actions
            HStack(spacing: 0) {
                Button {
                    openSettings()
                    NSApp.activate()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gear")
                            .font(.system(size: 11))
                        Text("Settings")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                            .font(.system(size: 11))
                        Text("Quit")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 280)
    }
}

// MARK: - Menu Action Button

struct MenuActionButton: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 32, height: 32)

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(iconColor)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Modern Portfolio View

struct ModernPortfolioView: View {
    @State private var state = AppState.shared
    private let auth = KiteAuthManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                    Text("Portfolio")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if state.kiteIsRefreshing {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                }

                Button {
                    Task { await auth.refreshPortfolio() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Summary
            let totalValue = totalPortfolioValue
            let totalPnL = totalPortfolioPnL

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(formatCurrency(totalValue))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(formatPnL(totalPnL))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(totalPnL >= 0 ? .green : .red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(totalPnL >= 0 ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    )
            }

            // Holdings list
            if state.kiteHoldings.isEmpty {
                if state.kiteIsLoading {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.6)
                        Text("Loading…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(state.kiteHoldings.prefix(5)) { holding in
                        HoldingRow(holding: holding)
                        if holding.id != state.kiteHoldings.prefix(5).last?.id {
                            Divider()
                                .opacity(0.3)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )

                if state.kiteHoldings.count > 5 {
                    Text("+ \(state.kiteHoldings.count - 5) more")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }

            if let updated = state.kiteLastUpdated {
                Text("Updated \(formatTime(updated))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .task {
            if state.kiteHoldings.isEmpty && !state.kiteIsLoading && !state.kiteIsRefreshing {
                await auth.refreshPortfolio()
            }
        }
    }

    // MARK: - Computed

    private var totalPortfolioValue: Double {
        state.kiteHoldings.reduce(0.0) { sum, h in
            sum + Double(h.quantity ?? 0) * (h.last_price ?? 0)
        }
    }

    private var totalPortfolioPnL: Double {
        state.kiteHoldings.reduce(0.0) { $0 + ($1.pnl ?? 0) }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_IN")
        return "₹\(formatter.string(from: NSNumber(value: value)) ?? "0.00")"
    }

    private func formatPnL(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)₹\(String(format: "%.2f", value))"
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Holding Row

struct HoldingRow: View {
    let holding: KiteHolding

    var body: some View {
        HStack(spacing: 4) {
            Text(holding.tradingsymbol)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let qty = holding.quantity {
                Text("×\(qty)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let ltp = holding.last_price {
                Text(formatCurrency(ltp))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }

            if let pnl = holding.pnl {
                Text(formatPnL(pnl))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(pnl >= 0 ? .green : .red)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_IN")
        return "₹\(formatter.string(from: NSNumber(value: value)) ?? "0.00")"
    }

    private func formatPnL(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)₹\(String(format: "%.2f", value))"
    }
}
