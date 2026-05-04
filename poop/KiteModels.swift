import Foundation

// MARK: - Auth

struct KiteAuthResponse: Codable {
    let status: String?
    let data: KiteAuthData?
    let message: String?
    let error_type: String?
}

struct KiteAuthData: Codable {
    let access_token: String?
    let public_token: String?
    let user_id: String?
    let user_name: String?
    let user_shortname: String?
    let avatar_url: String?
    let broker: String?
    let exchanges: [String]?
    let products: [String]?
    let order_types: [String]?
    let email: String?
    let user_type: String?
}

// MARK: - Portfolio Holdings

struct KiteHolding: Codable, Identifiable {
    let tradingsymbol: String
    let exchange: String
    let isin: String?
    let quantity: Int?
    let authorised_quantity: Int?
    let product: String?
    let collateral_quantity: Int?
    let collateral_type: String?
    let discrepancy: Bool?
    var average_price: Double?
    var last_price: Double?
    let close_price: Double?
    var pnl: Double?
    let day_change: Double?
    let day_change_percentage: Double?
    let instrument_token: String?
    let ticker: String?
    let realised_quantity: Int?
    let t1_quantity: Int?
    let utilised_quantity: Int?
    let pledged_quantity: Int?

    var id: String { "\(tradingsymbol)_\(exchange)" }
}

// MARK: - Mutual Fund Holdings

struct KiteMFHolding: Codable, Identifiable {
    let tradingsymbol: String
    let fund: String?
    let folio: String?
    let last_price: Double?
    let quantity: Double?
    var pnl: Double?
    let average_price: Double?

    var id: String { "\(tradingsymbol)_\(folio ?? "")" }
}

// MARK: - Positions

struct KitePosition: Codable, Identifiable {
    let tradingsymbol: String
    let exchange: String
    let instrument_token: String?
    let product: String?
    let quantity: Int?
    let overnight_quantity: Int?
    let multiplier: Int?
    var average_price: Double?
    var last_price: Double?
    let close_price: Double?
    var pnl: Double?
    let day_change: Double?
    let day_change_percentage: Double?
    let value: Double?
    let buy_quantity: Int?
    let sell_quantity: Int?
    let buy_value: Double?
    let sell_value: Double?
    let buy_m2m: Int?
    let sell_m2m: Int?
    let unrealised: Int?
    let realised: Int?
    let net_quantity: Int?

    var id: String { "\(tradingsymbol)_\(exchange)_\(product ?? "")" }
}

// MARK: - Generic API envelope

struct KiteAPIEnvelope<T: Codable>: Codable {
    let status: String?
    let data: T?
    let message: String?
    let error_type: String?
}
