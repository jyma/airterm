import CryptoKit
import Foundation

/// Drives the Mac side of the pairing flow against the relay server. The
/// Mac is the Noise IK responder: it owns a long-lived static keypair
/// (loaded via `KeyStore` on init) whose public key is embedded in the QR
/// the phone scans. After the phone POSTs `/api/pair/complete`, the
/// server pushes a `pair_completed` notification on the Mac's WS
/// connection and the Noise handshake begins inside the relay channel.
///
/// This file currently covers stages 1–2 of the pairing pipeline:
///   1. POST /api/pair/init → pair code + JWT mac token + ttl
///   2. v2 QR payload generation (server URL, pair code, mac device id,
///      mac static public key)
///
/// Noise IK handshake driving + SDP/ICE relay handling land in the next
/// slice; the API surface here is intentionally shaped so that handshake
/// code can plug in without rewriting the HTTP / QR concerns.
final class PairingService: @unchecked Sendable {
    private let serverURL: String
    private let macDeviceId: String
    private let macName: String
    private let identity: StaticIdentity

    init(serverURL: String, macDeviceId: String, macName: String) {
        self.serverURL = serverURL
        self.macDeviceId = macDeviceId
        self.macName = macName
        self.identity = KeyStore.loadOrCreateStaticIdentity()
    }

    /// Base64-encoded raw 32-byte X25519 public key. Phone reads this from
    /// the QR payload and uses it as the responder static for IK.
    var macPublicKeyBase64: String { identity.publicKeyBase64 }

    /// The relay base URL the panel uses to open its WS connection.
    var relayServerURL: String { serverURL }

    /// The stable Mac device id sent on every pair-init / WS handshake.
    var deviceId: String { macDeviceId }

    /// HTTP /api/pair/init. Returns the relay-allocated short pair code,
    /// the Mac JWT token (used to open the WS), and a unix timestamp at
    /// which the pair code expires.
    func initiatePairing() async throws -> PairInfo {
        guard let url = URL(string: "\(serverURL)/api/pair/init") else {
            throw PairingError.invalidServerURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "macDeviceId": macDeviceId,
            "macName": macName,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw PairingError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw PairingError.serverError(status: http.statusCode)
        }

        return try JSONDecoder().decode(PairInfo.self, from: data)
    }

    /// Builds a v2 QR payload that includes the Mac's static X25519
    /// public key. Scope: pure construction; the caller is responsible
    /// for rendering the result as a QR image and invalidating it once
    /// `pairCode` expires.
    func generateQRPayload(pairCode: String) -> QRCodePayload {
        QRCodePayload(
            server: serverURL,
            pairCode: pairCode,
            macDeviceId: macDeviceId,
            macPublicKey: identity.publicKeyBase64
        )
    }
}

enum PairingError: Error, LocalizedError {
    case invalidServerURL
    case serverError(status: Int)
    case invalidResponse
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: return "Invalid relay server URL"
        case .serverError(let status): return "Server returned HTTP \(status)"
        case .invalidResponse: return "Unexpected server response"
        case .timeout: return "Pairing timed out"
        }
    }
}
