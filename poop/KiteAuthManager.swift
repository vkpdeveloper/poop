import Foundation
import AppKit
import OSLog

@Observable
class KiteAuthManager {
    static let shared = KiteAuthManager()

    var isLoggingIn = false
    var authError: String?
    var loginSuccessMessage: String?

    private let settings = SettingsManager.shared
    private let server = KiteHTTPServer.shared
    private let service = KiteService.shared
    private var backgroundRefreshTimer: Timer?

    func beginLogin() {
        let apiKey = settings.kiteApiKey.trimmingCharacters(in: .whitespaces)
        let apiSecret = settings.kiteApiSecret.trimmingCharacters(in: .whitespaces)

        guard !apiKey.isEmpty, !apiSecret.isEmpty else {
            authError = "Please enter both API Key and API Secret."
            return
        }

        guard !isLoggingIn else {
            Logger.kite.notice("Login already in progress")
            return
        }

        isLoggingIn = true
        authError = nil

        server.stop()

        let started = server.start { [weak self] requestToken in
            guard let self else { return }
            Task { @MainActor in
                await self.handleCallback(requestToken: requestToken)
            }
        }

        guard started else {
            isLoggingIn = false
            authError = "Could not start local server on port 23864."
            return
        }

        let loginURL = "https://kite.trade/connect/login?v=3&api_key=\(apiKey)"
        guard let url = URL(string: loginURL) else {
            server.stop()
            isLoggingIn = false
            authError = "Invalid login URL."
            return
        }

        Logger.kite.info("Opening Kite login: \(loginURL)")
        NSWorkspace.shared.open(url)
    }

    func logout() {
        stopBackgroundRefresh()
        server.stop()
        settings.kiteAccessToken = ""
        AppState.shared.kiteHoldings = []
        AppState.shared.kiteMFHoldings = []
        AppState.shared.kitePositions = []
        AppState.shared.kiteLastUpdated = nil
        authError = nil
        loginSuccessMessage = nil
        isLoggingIn = false
        Logger.kite.info("Logged out of Kite")
    }

    func restoreSession() {
        let token = settings.kiteAccessToken
        guard !token.isEmpty else {
            Logger.kite.debug("No saved Kite session")
            stopBackgroundRefresh()
            return
        }

        Logger.kite.info("Found saved Kite session — refreshing holdings")
        Task { @MainActor in
            await refreshPortfolio()
            startBackgroundRefresh()
        }
    }

    // MARK: - Background Refresh

    func startBackgroundRefresh() {
        guard backgroundRefreshTimer == nil else { return }
        Logger.kite.info("Starting background refresh every 1 hour")
        backgroundRefreshTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard !self.settings.kiteAccessToken.isEmpty else {
                    self.stopBackgroundRefresh()
                    return
                }
                await self.refreshPortfolio()
            }
        }
        // Fire immediately so the timer is on a fresh schedule
        backgroundRefreshTimer?.tolerance = 60
    }

    func stopBackgroundRefresh() {
        backgroundRefreshTimer?.invalidate()
        backgroundRefreshTimer = nil
        Logger.kite.debug("Stopped background refresh")
    }

    // MARK: - Private

    @MainActor
    private func handleCallback(requestToken: String) async {
        Logger.kite.info("Exchanging request token…")
        do {
            try await service.exchangeToken(requestToken: requestToken)
            isLoggingIn = false
            loginSuccessMessage = "Connected to Kite!"
            authError = nil
            Logger.kite.info("Kite login successful")
            startBackgroundRefresh()
            await refreshPortfolio()

            // Clear the success message after a few seconds
            try? await Task.sleep(for: .seconds(3))
            loginSuccessMessage = nil
        } catch {
            isLoggingIn = false
            authError = error.localizedDescription
            Logger.kite.error("Kite login failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    func refreshPortfolio() async {
        guard !settings.kiteAccessToken.isEmpty else { return }

        let state = AppState.shared
        let isFirstLoad = state.kiteHoldings.isEmpty && state.kiteMFHoldings.isEmpty && state.kitePositions.isEmpty

        if isFirstLoad {
            state.kiteIsLoading = true
        } else {
            state.kiteIsRefreshing = true
        }

        defer {
            state.kiteIsLoading = false
            state.kiteIsRefreshing = false
            state.kiteLastUpdated = Date()
        }

        do {
            let holdings = try await service.fetchHoldings()
            state.kiteHoldings = holdings
            Logger.kite.info("Fetched \(holdings.count) holdings")
        } catch {
            Logger.kite.error("Failed to fetch holdings: \(error.localizedDescription)")
            // Keep existing data — transient network errors shouldn't blank the UI
        }

        do {
            let mfHoldings = try await service.fetchMFHoldings()
            state.kiteMFHoldings = mfHoldings
            Logger.kite.info("Fetched \(mfHoldings.count) MF holdings")
        } catch {
            Logger.kite.error("Failed to fetch MF holdings: \(error.localizedDescription)")
        }

        do {
            let positions = try await service.fetchPositions()
            state.kitePositions = positions
            Logger.kite.info("Fetched \(positions.count) positions")
        } catch {
            Logger.kite.error("Failed to fetch positions: \(error.localizedDescription)")
        }
    }
}
