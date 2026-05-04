import SwiftUI

struct KitePortfolioView: View {
    @State private var state = AppState.shared
    private let auth = KiteAuthManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            portfolioSummary
            mutualFundSection
            footer
        }
        .task {
            if state.kiteMFHoldings.isEmpty && !state.kiteIsLoading && !state.kiteIsRefreshing {
                await auth.refreshPortfolio()
            }
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var portfolioSummary: some View {
        let totalValue = totalPortfolioValue
        let totalInvested = totalPortfolioInvested
        let totalPnL = totalPortfolioPnL

        HStack {
            Text("Portfolio")
                .font(.headline)
            Spacer()
            if state.kiteIsRefreshing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }
            Text(formatCurrency(totalValue))
                .font(.headline)
                .monospacedDigit()
        }
        .padding(.vertical, 4)

        HStack {
            Text("Invested")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatCurrency(totalInvested))
                .font(.caption)
                .monospacedDigit()
        }

        HStack {
            Text(totalPnL >= 0 ? "Gain" : "Loss")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatPnL(totalPnL))
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(totalPnL >= 0 ? .green : .red)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Mutual Fund Holdings

    @ViewBuilder
    private var mutualFundSection: some View {
        if state.kiteMFHoldings.isEmpty {
            if state.kiteIsLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading mutual fund holdings…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                Text("No holdings")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            }
        } else {
            Divider()

            ForEach(state.kiteMFHoldings.prefix(5)) { holding in
                HStack(spacing: 4) {
                    Text(holding.fund ?? holding.tradingsymbol)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let qty = holding.quantity {
                        Text("×\(formatQuantity(qty))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if let ltp = holding.last_price {
                        Text(formatCurrency(ltp))
                            .font(.subheadline)
                            .monospacedDigit()
                            .frame(width: 80, alignment: .trailing)
                    }
                    if let pnl = holdingPnL(for: holding) {
                        Text(formatPnL(pnl))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(pnl >= 0 ? .green : .red)
                            .frame(width: 72, alignment: .trailing)
                    }
                }
                .padding(.vertical, 1)
            }

            if state.kiteMFHoldings.count > 5 {
                Text("+ \(state.kiteMFHoldings.count - 5) more…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 4) {
            Divider()

            HStack {
                if let updated = state.kiteLastUpdated {
                    Text("Updated \(formatTime(updated))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text(auth.loginSuccessMessage ?? "")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Computed

    private var totalPortfolioValue: Double {
        state.kiteMFHoldings.reduce(0.0) { sum, h in
            sum + (h.quantity ?? 0) * (h.last_price ?? 0)
        }
    }

    private var totalPortfolioInvested: Double {
        state.kiteMFHoldings.reduce(0.0) { sum, h in
            sum + (h.quantity ?? 0) * (h.average_price ?? 0)
        }
    }

    private var totalPortfolioPnL: Double {
        totalPortfolioValue - totalPortfolioInvested
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

    private func formatQuantity(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.3f", value)
    }

    private func holdingPnL(for holding: KiteMFHolding) -> Double? {
        guard let quantity = holding.quantity,
              let averagePrice = holding.average_price,
              let lastPrice = holding.last_price else {
            return nil
        }

        return (quantity * lastPrice) - (quantity * averagePrice)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}
