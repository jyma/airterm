import Foundation

/// Stable per-install Mac device id used as `macDeviceId` in pairing
/// requests + as the WS connection's identity. The first call generates
/// a UUID and persists it; every subsequent call returns the same value.
///
/// Storage is UserDefaults (suite the app already owns) — the same
/// caveat as `KeyStore` applies for shipping builds: rotate to Keychain
/// once the wider crypto storage migration lands.
enum MacDeviceID {
    private static let key = "airterm.identity.macDeviceId"

    static func stableId() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let fresh = "mac-\(UUID().uuidString.lowercased())"
        defaults.set(fresh, forKey: key)
        return fresh
    }

    /// Tests / explicit user reset only — invalidates every existing
    /// pairing on the relay server (the device id is the WS identity).
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
