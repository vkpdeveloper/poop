import Foundation
import CryptoKit
import OSLog

enum KiteError: LocalizedError {
    case missingCredentials
    case notLoggedIn
    case invalidURL(String)
    case authFailed
    case networkError(String)
    case apiError(Int, String)
    case decodingError(String)
    case tokenExpired

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Kite API key and secret are required."
        case .notLoggedIn:
            return "Not logged in to Kite. Open Settings to connect."
        case .invalidURL(let url):
            return "Invalid Kite API URL: \(url)"
        case .authFailed:
            return "Kite authentication failed. Check your API key and secret."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .apiError(let code, let msg):
            return "Kite API error \(code): \(msg)"
        case .decodingError(let msg):
            return "Failed to parse Kite response: \(msg)"
        case .tokenExpired:
            return "Kite session expired. Please log in again."
        }
    }
}

class KiteService {
    static let shared = KiteService()
    private init() {}

    private let session = URLSession.shared
    private let baseURL = "https://api.kite.trade"
    private let kiteVersion = "3"

    private var apiKey: String { SettingsManager.shared.kiteApiKey }
    private var apiSecret: String { SettingsManager.shared.kiteApiSecret }
    private var accessToken: String { SettingsManager.shared.kiteAccessToken }

    private var authHeader: String? {
        guard !accessToken.isEmpty, !apiKey.isEmpty else { return nil }
        return "token \(apiKey):\(accessToken)"
    }

    // MARK: - Checksum

    private func checksum(apiKey: String, requestToken: String, apiSecret: String) -> String {
        let input = apiKey + requestToken + apiSecret
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Token Exchange

    func exchangeToken(requestToken: String) async throws {
        guard !apiKey.isEmpty, !apiSecret.isEmpty else {
            Logger.kite.error("Missing Kite credentials")
            throw KiteError.missingCredentials
        }

        let cs = checksum(apiKey: apiKey, requestToken: requestToken, apiSecret: apiSecret)

        let urlString = "\(baseURL)/session/token"
        guard let url = URL(string: urlString) else {
            throw KiteError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(kiteVersion, forHTTPHeaderField: "X-Kite-Version")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = "api_key=\(percentEncode(apiKey))&request_token=\(percentEncode(requestToken))&checksum=\(percentEncode(cs))"
        request.httpBody = body.data(using: .utf8)

        Logger.kite.info("Exchanging request token…")

        let (data, _) = try await perform(request: request)

        let envelope = try JSONDecoder().decode(KiteAPIEnvelope<KiteAuthData>.self, from: data)

        guard envelope.status == "success", let authData = envelope.data, let token = authData.access_token else {
            let msg = envelope.message ?? envelope.error_type ?? "Unknown error"
            Logger.kite.error("Token exchange failed: \(msg)")
            throw KiteError.authFailed
        }

        SettingsManager.shared.kiteAccessToken = token
        Logger.kite.info("Access token saved (user: \(authData.user_name ?? "?"))")
    }

    // MARK: - Holdings

    func fetchHoldings() async throws -> [KiteHolding] {
        guard let auth = authHeader else { throw KiteError.notLoggedIn }

        let urlString = "\(baseURL)/portfolio/holdings"
        var holdings = try await kiteGET(urlString: urlString, auth: auth, as: [KiteHolding].self)

        // Kite sends average_price / last_price / pnl as sometimes non-numeric "XX"
        // Normalise by stripping commas and re-parsing
        holdings = holdings.map { h in
            var h = h
            if h.average_price == nil { h.average_price = parseNumeric(fromRaw: h) }
            if h.last_price    == nil { h.last_price    = parseNumeric(fromRaw: h) }
            if h.pnl           == nil, let raw = rawDouble(fromRaw: h, key: "pnl") { h.pnl = raw }
            return h
        }

        return holdings
    }

    func fetchMFHoldings() async throws -> [KiteMFHolding] {
        guard let auth = authHeader else { throw KiteError.notLoggedIn }

        let urlString = "\(baseURL)/mf/holdings"
        var holdings = try await kiteGET(urlString: urlString, auth: auth, as: [KiteMFHolding].self)

        holdings = holdings.map { h in
            var h = h
            if h.pnl == nil, let raw = rawDouble(fromRaw: h, key: "pnl") { h.pnl = raw }
            return h
        }

        return holdings
    }

    func fetchPositions() async throws -> [KitePosition] {
        guard let auth = authHeader else { throw KiteError.notLoggedIn }

        let urlString = "\(baseURL)/portfolio/positions"
        var positions = try await kiteGET(urlString: urlString, auth: auth, as: KitePositionsEnvelope.self)

        positions.net = positions.net?.map { p in
            var p = p
            if p.pnl == nil, let raw = rawDouble(fromRaw: p, key: "pnl") { p.pnl = raw }
            return p
        }

        return positions.net ?? []
    }

    // MARK: - Generic GET

    private func kiteGET<T: Codable>(urlString: String, auth: String, as type: T.Type) async throws -> T {
        guard let url = URL(string: urlString) else {
            throw KiteError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(kiteVersion, forHTTPHeaderField: "X-Kite-Version")
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        Logger.kite.debug("GET \(urlString)")

        let (data, _) = try await perform(request: request)

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Logger.kite.warning("Direct decode failed, trying envelope: \(error.localizedDescription)")
            let envelope = try JSONDecoder().decode(KiteAPIEnvelope<T>.self, from: data)
            guard envelope.status == "success", let inner = envelope.data else {
                let msg = envelope.message ?? envelope.error_type ?? "Unknown error"
                throw KiteError.apiError(0, msg)
            }
            return inner
        }
    }

    // MARK: - HTTP

    private func perform(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Logger.kite.error("Network error: \(error.localizedDescription)")
            throw KiteError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw KiteError.networkError("Unexpected response type")
        }

        if http.statusCode == 403 {
            // Token likely expired
            SettingsManager.shared.kiteAccessToken = ""
            throw KiteError.tokenExpired
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            Logger.kite.error("API error \(http.statusCode): \(body)")
            throw KiteError.apiError(http.statusCode, body)
        }

        return (data, http)
    }

    // MARK: - Helpers

    private func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    /// Kite sometimes sends numeric fields as non-numeric strings like "XX"
    /// The raw JSON is re-parsed to extract the real Double if present.
    private func parseNumeric<T: Codable>(fromRaw item: T) -> Double? {
        guard let raw = rawJSON(item) else { return nil }
        for key in ["average_price", "last_price", "pnl"] {
            if let val = raw[key] as? Double { return val }
            if let val = raw[key] as? Int    { return Double(val) }
        }
        // Return the first numeric value found among those keys
        for key in ["average_price", "last_price", "pnl"] {
            if let val = raw[key] as? Double { return val }
            if let val = raw[key] as? Int    { return Double(val) }
        }
        return nil
    }

    private func rawDouble<T: Codable>(fromRaw item: T, key: String) -> Double? {
        guard let raw = rawJSON(item) else { return nil }
        if let val = raw[key] as? Double { return val }
        if let val = raw[key] as? Int    { return Double(val) }
        return nil
    }

    private func rawJSON<T: Codable>(_ value: T) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(value),
              let raw  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return raw
    }
}

/// The positions endpoint wraps `net` array inside an outer object.
private struct KitePositionsEnvelope: Codable {
    struct Day: Codable { var net: [KitePosition]? }
    let day: [Day]?
    var net: [KitePosition]?
}
