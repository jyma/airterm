import Foundation

/// On-disk record of every phone the Mac has successfully paired with.
/// Stored as JSON inside `UserDefaults` because the data is non-sensitive
/// device metadata (no secret keys here — those live in `KeyStore`). The
/// Mac's own relay JWT token is held separately for the same reason: the
/// pairing list is read by UI, the token by the relay client.
///
/// Production note: phone public keys eventually arrive in this record
/// (P3-4b will start sending them), at which point the JSON gets a
/// `phonePublicKey` field. Backwards-compat is handled by the optional
/// decode path.
struct PairedPhone: Codable, Sendable, Equatable {
    let deviceId: String
    let name: String
    let pairedAt: Date
    let publicKey: String?
}

/// Source of truth for the Mac's pairing list and current relay JWT.
/// All accessors are synchronous and main-thread safe (UserDefaults is
/// thread-safe but we keep callers single-threaded for simplicity).
enum PairingStore {
    private static let pairedPhonesKey = "airterm.pairedPhones.v1"
    private static let macTokenKey     = "airterm.macToken.v1"

    // MARK: - Paired phones

    static func loadPairedPhones() -> [PairedPhone] {
        guard let data = UserDefaults.standard.data(forKey: pairedPhonesKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([PairedPhone].self, from: data)
        } catch {
            DebugLog.log("PairingStore: paired list decode failed (\(error)), discarding")
            UserDefaults.standard.removeObject(forKey: pairedPhonesKey)
            return []
        }
    }

    /// Adds (or refreshes) a phone in the persisted list. Existing entries
    /// keyed by `deviceId` are updated in place — repeated pairings of the
    /// same phone don't duplicate. Order is "most recently paired last".
    static func addOrUpdate(_ phone: PairedPhone) {
        var phones = loadPairedPhones().filter { $0.deviceId != phone.deviceId }
        phones.append(phone)
        save(phones)
    }

    static func remove(deviceId: String) {
        let phones = loadPairedPhones().filter { $0.deviceId != deviceId }
        save(phones)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: pairedPhonesKey)
        UserDefaults.standard.removeObject(forKey: macTokenKey)
    }

    private static func save(_ phones: [PairedPhone]) {
        do {
            let data = try JSONEncoder().encode(phones)
            UserDefaults.standard.set(data, forKey: pairedPhonesKey)
        } catch {
            DebugLog.log("PairingStore: paired list encode failed (\(error))")
        }
    }

    // MARK: - Mac relay token

    /// Persisted relay JWT so the Mac can reconnect across launches without
    /// re-running pair-init. The token is opaque and doesn't authorise
    /// anything beyond opening a WS to the relay; pairings are tracked
    /// server-side by `pair_completed` records.
    static func loadMacToken() -> String? {
        let value = UserDefaults.standard.string(forKey: macTokenKey)
        return (value?.isEmpty ?? true) ? nil : value
    }

    static func saveMacToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: macTokenKey)
    }
}
