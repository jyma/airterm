import Foundation

struct PairInfo: Codable, Sendable {
    let pairId: String
    let pairCode: String
    let expiresAt: Int
    let token: String
}

struct PairedDevice: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let role: String
    let token: String
    let pairedAt: Date
}

struct QRCodePayload: Codable, Sendable {
    let server: String
    let pairCode: String
    let macDeviceId: String
}
