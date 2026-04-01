import Foundation

/// Manages the pairing flow with the relay server.
final class PairingService: @unchecked Sendable {
    private let serverURL: String
    private let macDeviceId: String
    private let macName: String

    init(serverURL: String, macDeviceId: String, macName: String) {
        self.serverURL = serverURL
        self.macDeviceId = macDeviceId
        self.macName = macName
    }

    /// Initiate pairing — returns pair info for QR code generation
    func initiatePairing() async throws -> PairInfo {
        let url = URL(string: "\(serverURL)/api/pair/init")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "macDeviceId": macDeviceId,
            "macName": macName,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PairingError.serverError
        }

        let result = try JSONDecoder().decode(PairInfo.self, from: data)
        return result
    }

    /// Generate QR code payload
    func generateQRPayload(pairCode: String) -> QRCodePayload {
        QRCodePayload(
            server: serverURL,
            pairCode: pairCode,
            macDeviceId: macDeviceId
        )
    }
}

enum PairingError: Error, LocalizedError {
    case serverError
    case timeout
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .serverError: return "Server error during pairing"
        case .timeout: return "Pairing timed out"
        case .invalidResponse: return "Invalid server response"
        }
    }
}
