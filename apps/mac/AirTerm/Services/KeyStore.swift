import CryptoKit
import Foundation

/// Persists AirTerm's long-lived X25519 static keypair across launches. The
/// static key is the responder identity in the Noise IK handshake — the
/// phone gets it from the QR code and uses it to start the handshake. Once
/// generated it must not change (rotating breaks every existing pairing).
///
/// Storage: this MVP uses `UserDefaults` keyed under the application's
/// suite. It's adequate for ad-hoc development builds but a shipping
/// product must move the static private key to Keychain (with
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) to defend against
/// Library-level reads. The pubkey can stay in UserDefaults.
///
/// Wire format: 32-byte raw X25519 keys, base64-encoded. The TS protocol
/// package's QRCodePayloadV2 expects exactly this shape.
enum KeyStore {
    private static let privateKeyDefaultsKey = "airterm.identity.privateKey.b64"
    private static let pubKeyDefaultsKey     = "airterm.identity.publicKey.b64"

    /// In-memory loaded identity. Generated and persisted on first call;
    /// every subsequent call returns the same keypair.
    static func loadOrCreateStaticIdentity() -> StaticIdentity {
        if let identity = loadFromDefaults() {
            return identity
        }
        return generateAndPersist()
    }

    /// Nukes the persisted identity. ONLY for tests / explicit user reset —
    /// rotating the static key invalidates every existing pairing.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: privateKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: pubKeyDefaultsKey)
    }

    // MARK: - Internals

    private static func loadFromDefaults() -> StaticIdentity? {
        let defaults = UserDefaults.standard
        guard
            let privB64 = defaults.string(forKey: privateKeyDefaultsKey),
            let pubB64  = defaults.string(forKey: pubKeyDefaultsKey),
            let privData = Data(base64Encoded: privB64),
            let pubData = Data(base64Encoded: pubB64)
        else {
            return nil
        }
        do {
            let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privData)
            let derivedPub = privateKey.publicKey.rawRepresentation
            // Defensive: if the on-disk public key doesn't match the one we
            // derive from the private key, the storage was tampered with.
            // Regenerate rather than ship a corrupt identity.
            guard derivedPub == pubData else {
                DebugLog.log("KeyStore: stored pubkey mismatched derived pubkey, regenerating")
                return nil
            }
            return StaticIdentity(
                privateKey: privateKey,
                publicKeyBase64: pubB64,
                publicKeyData: pubData
            )
        } catch {
            DebugLog.log("KeyStore: rejected stored private key (\(error)), regenerating")
            return nil
        }
    }

    private static func generateAndPersist() -> StaticIdentity {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let pubData = privateKey.publicKey.rawRepresentation
        let pubB64 = pubData.base64EncodedString()
        let privB64 = privateKey.rawRepresentation.base64EncodedString()
        let defaults = UserDefaults.standard
        defaults.set(privB64, forKey: privateKeyDefaultsKey)
        defaults.set(pubB64, forKey: pubKeyDefaultsKey)
        return StaticIdentity(
            privateKey: privateKey,
            publicKeyBase64: pubB64,
            publicKeyData: pubData
        )
    }
}

/// One AirTerm install's long-lived Noise IK responder identity. The
/// private key never leaves the device; the public key is what the phone
/// sees when it scans the QR.
struct StaticIdentity {
    let privateKey: Curve25519.KeyAgreement.PrivateKey
    let publicKeyBase64: String
    let publicKeyData: Data
}
