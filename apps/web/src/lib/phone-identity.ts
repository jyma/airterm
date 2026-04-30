import { generateNoiseKeyPair, publicKeyFromPrivate, type NoiseKeyPair } from '@airterm/crypto'
import { deleteKey, loadKey, storeKey } from './key-store'

/// Persists the phone's long-lived X25519 static keypair across browser
/// sessions. Mirrors the role of `KeyStore.swift` on Mac: the Noise IK
/// initiator (the phone) needs a stable static key so a re-paired Mac
/// can recognise "this is the same phone" in future sessions.
///
/// Storage: IndexedDB via the existing `key-store.ts` helpers. The raw
/// 32-byte private key is stored as bytes; the public key is derived on
/// every load (IndexedDB is per-origin, not transmittable, so storing
/// the private material there is appropriate for an MVP — production
/// builds may want to push this behind WebAuthn or an OPFS-encrypted
/// blob if/when threat model tightens).

const PHONE_STATIC_PRIVATE_KEY = 'phone.static.privateKey'

/// Loaded form of the phone's static identity. Both halves are raw
/// 32-byte Uint8Array — the same shape `HandshakeState` accepts.
export interface PhoneIdentity {
  readonly keyPair: NoiseKeyPair
  /// `true` when this load just minted a fresh keypair (callers can use
  /// this to log "first launch" telemetry or surface a one-time hint).
  readonly freshlyGenerated: boolean
}

export async function loadOrCreatePhoneIdentity(): Promise<PhoneIdentity> {
  const existing = await loadKey(PHONE_STATIC_PRIVATE_KEY)
  if (existing && existing.length === 32) {
    return {
      keyPair: derivePublicKey(existing),
      freshlyGenerated: false,
    }
  }

  const fresh = generateNoiseKeyPair()
  await storeKey(PHONE_STATIC_PRIVATE_KEY, fresh.privateKey)
  return {
    keyPair: fresh,
    freshlyGenerated: true,
  }
}

/// Tests / explicit user reset only. Like the Mac side, rotating the
/// phone's static key invalidates every existing pairing.
export async function resetPhoneIdentity(): Promise<void> {
  await deleteKey(PHONE_STATIC_PRIVATE_KEY)
}

/// Recovers the public key from a stored private key by re-running
/// X25519 base-point multiplication. Cheaper and safer than persisting
/// both halves in lockstep — there's no way for the loaded record to
/// "drift" if the storage layer ever truncates one of the keys.
function derivePublicKey(privateKey: Uint8Array): NoiseKeyPair {
  return {
    privateKey,
    publicKey: publicKeyFromPrivate(privateKey),
  }
}
