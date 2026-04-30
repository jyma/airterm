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

/// QR payload v2 — bumped to carry the Mac's static X25519 public key the
/// phone needs to initiate the Noise IK handshake. `v` is fixed at 2 so
/// older phone builds reading a v1 QR can detect they're out of date.
///
/// Mirrors `QRCodePayloadV2` in `packages/protocol/src/pairing.ts` —
/// any field rename here must follow there.
struct QRCodePayload: Codable, Sendable {
    let v: Int
    let server: String
    let pairCode: String
    let macDeviceId: String
    let macPublicKey: String

    init(server: String, pairCode: String, macDeviceId: String, macPublicKey: String) {
        self.v = 2
        self.server = server
        self.pairCode = pairCode
        self.macDeviceId = macDeviceId
        self.macPublicKey = macPublicKey
    }

    /// JSON-encoded form suitable for embedding into a QR code. Compact
    /// (no whitespace) to keep the QR small enough for fast camera scans.
    func encodedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw QRCodeError.encodingFailed
        }
        return string
    }

    enum QRCodeError: Error { case encodingFailed }
}
