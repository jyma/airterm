// Noise Protocol IK pattern — Curve25519 + ChaCha20-Poly1305 + SHA256.
//
// We implement only what AirTerm needs:
//   • Pattern: IK (responder static is known to initiator out-of-band — the
//     phone learns the Mac's static via the QR code).
//   • DH:    X25519
//   • AEAD:  ChaCha20-Poly1305 with a 12-byte counter nonce (4 zeroes ||
//            uint64-LE counter), per the Noise spec.
//   • Hash:  SHA-256
//
// References:
//   - Noise spec rev 34: https://noiseprotocol.org/noise.html
//   - SymmetricState §5.2, HandshakeState §5.3, IK pattern §7.5
//
// This file is a *reference implementation* — both ends of AirTerm
// (the Mac Swift side and the phone web side) must agree on it
// byte-for-byte. Round-trip tests in noise.test.ts verify the two
// halves derive identical transport keys; cross-language interop
// (Mac responder + Web initiator) is enforced by sharing the
// protocol-name string and message wire format with the Swift port.

import { x25519 } from '@noble/curves/ed25519'
import { chacha20poly1305 } from '@noble/ciphers/chacha'
import { sha256 } from '@noble/hashes/sha2'
import { hmac } from '@noble/hashes/hmac'

export const NOISE_PROTOCOL_NAME = 'Noise_IK_25519_ChaChaPoly_SHA256'
export const DHLEN = 32
export const HASHLEN = 32
export const TAGLEN = 16
const NONCE_LEN = 12

/// Per Noise spec §5.1: HKDF returns up to 3 outputs of HASHLEN each. We
/// only need 2 outputs in this implementation (mixKey, split, mixKeyAndHash
/// would need 3 — currently unused).
function hkdf2(chainingKey: Uint8Array, ikm: Uint8Array): [Uint8Array, Uint8Array] {
  const tempKey = hmac(sha256, chainingKey, ikm)
  const o1 = hmac(sha256, tempKey, new Uint8Array([0x01]))
  const o2 = hmac(sha256, tempKey, concat(o1, new Uint8Array([0x02])))
  return [o1, o2]
}

function concat(...parts: Uint8Array[]): Uint8Array {
  let total = 0
  for (const p of parts) total += p.length
  const out = new Uint8Array(total)
  let off = 0
  for (const p of parts) {
    out.set(p, off)
    off += p.length
  }
  return out
}

/// Build a 12-byte ChaCha20-Poly1305 nonce from a 64-bit counter, per the
/// Noise spec: 4 zero bytes || little-endian uint64.
function nonceBytes(counter: bigint): Uint8Array {
  const out = new Uint8Array(NONCE_LEN)
  // First 4 bytes are zero (already zero-initialised by Uint8Array).
  const view = new DataView(out.buffer)
  view.setBigUint64(4, counter, true) // little-endian
  return out
}

// ---- SymmetricState (§5.2) ----

/// Aggregates the chaining key (`ck`), running hash (`h`), and an optional
/// cipher key (`k`, plus monotonic counter `n`). All AEAD-protected
/// payloads in Noise pass through encryptAndHash / decryptAndHash, which
/// thread the running hash into the AEAD's AAD so any tampering with
/// either the ciphertext OR the transcript invalidates the tag.
export class SymmetricState {
  ck: Uint8Array = new Uint8Array(HASHLEN)
  h: Uint8Array = new Uint8Array(HASHLEN)
  k: Uint8Array | null = null
  n: bigint = 0n

  initialize(protocolName: string): void {
    const nameBytes = new TextEncoder().encode(protocolName)
    if (nameBytes.length <= HASHLEN) {
      this.h = new Uint8Array(HASHLEN)
      this.h.set(nameBytes, 0)
    } else {
      this.h = sha256(nameBytes)
    }
    this.ck = this.h.slice()
    this.k = null
    this.n = 0n
  }

  mixHash(data: Uint8Array): void {
    this.h = sha256(concat(this.h, data))
  }

  mixKey(material: Uint8Array): void {
    const [newCk, tempK] = hkdf2(this.ck, material)
    this.ck = newCk
    this.k = tempK.slice(0, 32) // truncate to 32 bytes (already 32 from sha256)
    this.n = 0n
  }

  /// Encrypts `plaintext` under `k` if a key is installed; threads the
  /// current hash through the AEAD as AAD; appends the resulting
  /// ciphertext to the running hash. When no key is installed
  /// (pre-mixKey messages), passes plaintext through unchanged but still
  /// mixes it into the hash.
  encryptAndHash(plaintext: Uint8Array): Uint8Array {
    let outBytes: Uint8Array
    if (this.k) {
      const cipher = chacha20poly1305(this.k, nonceBytes(this.n), this.h)
      outBytes = cipher.encrypt(plaintext)
      this.n += 1n
    } else {
      outBytes = plaintext
    }
    this.mixHash(outBytes)
    return outBytes
  }

  /// Inverse of encryptAndHash. Order matters: hash must be mixed with the
  /// ORIGINAL ciphertext bytes (not plaintext) so both sides keep parallel
  /// hash state.
  decryptAndHash(ciphertext: Uint8Array): Uint8Array {
    let plaintext: Uint8Array
    if (this.k) {
      const cipher = chacha20poly1305(this.k, nonceBytes(this.n), this.h)
      plaintext = cipher.decrypt(ciphertext)
      this.n += 1n
    } else {
      plaintext = ciphertext
    }
    this.mixHash(ciphertext)
    return plaintext
  }

  /// Final operation at the end of a handshake: derive two transport
  /// CipherStates from the chaining key. The first is initiator→responder,
  /// the second is responder→initiator. Caller (HandshakeState.finalize)
  /// picks the correct send/receive pairing based on its role.
  split(): [CipherState, CipherState] {
    const [k1, k2] = hkdf2(this.ck, new Uint8Array(0))
    return [new CipherState(k1.slice(0, 32)), new CipherState(k2.slice(0, 32))]
  }

  /// Snapshot the running hash. The caller can use it as a channel-binding
  /// token (Noise spec §11.2) to associate an out-of-band exchange with
  /// this handshake.
  getHandshakeHash(): Uint8Array {
    return this.h.slice()
  }
}

// ---- CipherState (§5.1) ----

/// Per-direction transport-mode AEAD with a counter-based nonce. After
/// HandshakeState.finalize() returns, callers use one CipherState for
/// outgoing frames and another for incoming.
export class CipherState {
  private k: Uint8Array
  private n: bigint = 0n

  constructor(key: Uint8Array) {
    if (key.length !== 32) throw new Error('CipherState key must be 32 bytes')
    this.k = key
  }

  /// Encrypts plaintext, optionally with `ad` as AEAD additional data.
  /// Increments the nonce counter. Throws if the counter would overflow
  /// 2^64 - 1 (caller MUST rekey or terminate the session before then).
  encrypt(plaintext: Uint8Array, ad: Uint8Array = new Uint8Array(0)): Uint8Array {
    if (this.n === 0xFFFFFFFFFFFFFFFFn) {
      throw new Error('Noise CipherState nonce exhausted; rekey required')
    }
    const cipher = chacha20poly1305(this.k, nonceBytes(this.n), ad)
    const out = cipher.encrypt(plaintext)
    this.n += 1n
    return out
  }

  decrypt(ciphertext: Uint8Array, ad: Uint8Array = new Uint8Array(0)): Uint8Array {
    if (this.n === 0xFFFFFFFFFFFFFFFFn) {
      throw new Error('Noise CipherState nonce exhausted; rekey required')
    }
    const cipher = chacha20poly1305(this.k, nonceBytes(this.n), ad)
    const out = cipher.decrypt(ciphertext)
    this.n += 1n
    return out
  }

  /// Current send/receive counter. Useful for the caller's seq accounting
  /// in EncryptedFrame at the signaling layer.
  get nonce(): bigint {
    return this.n
  }
}

// ---- HandshakeState (§5.3) for IK pattern (§7.5) ----
//
// IK pattern messages (rev 34, §7.5):
//   <- s            (responder static known out-of-band — the QR)
//   ...
//   -> e, es, s, ss
//   <- e, ee, se
//
// After both messages have been processed, both sides call split() to
// derive transport CipherStates.

export interface NoiseKeyPair {
  readonly publicKey: Uint8Array  // 32 bytes
  readonly privateKey: Uint8Array // 32 bytes
}

export interface HandshakeResult {
  readonly send: CipherState
  readonly receive: CipherState
  readonly handshakeHash: Uint8Array
}

export class HandshakeState {
  ss = new SymmetricState()
  s: NoiseKeyPair
  e: NoiseKeyPair | null = null
  rs: Uint8Array | null = null
  re: Uint8Array | null = null
  initiator: boolean

  /// `prologue` is mixed into the hash before any key material — typical
  /// uses are protocol-version bytes or QR payload bytes that both sides
  /// agree on out of band. Pass an empty Uint8Array if unused.
  constructor(opts: {
    initiator: boolean
    prologue: Uint8Array
    s: NoiseKeyPair
    rs?: Uint8Array
  }) {
    this.initiator = opts.initiator
    this.s = opts.s
    this.rs = opts.rs ?? null
    this.ss.initialize(NOISE_PROTOCOL_NAME)
    this.ss.mixHash(opts.prologue)
    // Pre-message: <- s
    if (this.initiator) {
      if (!this.rs) throw new Error('Noise IK initiator requires responder static (rs)')
      this.ss.mixHash(this.rs)
    } else {
      this.ss.mixHash(this.s.publicKey)
    }
  }

  /// Initiator → responder, message A: e, es, s, ss + payload.
  writeMessageA(payload: Uint8Array): Uint8Array {
    if (!this.initiator) throw new Error('Only the initiator writes message A')
    this.e = this.generateEphemeral()
    // -> e
    this.ss.mixHash(this.e.publicKey)
    // es
    this.ss.mixKey(x25519.getSharedSecret(this.e.privateKey, this.rs!))
    // s — encrypt our static under the current key
    const sCipher = this.ss.encryptAndHash(this.s.publicKey)
    // ss
    this.ss.mixKey(x25519.getSharedSecret(this.s.privateKey, this.rs!))
    const payloadCipher = this.ss.encryptAndHash(payload)
    return concat(this.e.publicKey, sCipher, payloadCipher)
  }

  /// Responder reads initiator's message A. Returns the decrypted payload.
  readMessageA(message: Uint8Array): Uint8Array {
    if (this.initiator) throw new Error('Only the responder reads message A')
    if (message.length < DHLEN + DHLEN + TAGLEN) {
      throw new Error('Noise IK message A is shorter than minimum length')
    }
    let off = 0
    // -> e
    this.re = message.slice(off, off + DHLEN)
    off += DHLEN
    this.ss.mixHash(this.re)
    // es (responder side: DH(s, re))
    this.ss.mixKey(x25519.getSharedSecret(this.s.privateKey, this.re))
    // s — decrypt the initiator's static
    const sCipher = message.slice(off, off + DHLEN + TAGLEN)
    off += DHLEN + TAGLEN
    this.rs = this.ss.decryptAndHash(sCipher)
    // ss
    this.ss.mixKey(x25519.getSharedSecret(this.s.privateKey, this.rs))
    // payload
    const payloadCipher = message.slice(off)
    return this.ss.decryptAndHash(payloadCipher)
  }

  /// Responder → initiator, message B: e, ee, se + payload.
  writeMessageB(payload: Uint8Array): Uint8Array {
    if (this.initiator) throw new Error('Only the responder writes message B')
    if (!this.re) throw new Error('Noise IK responder must read message A before writing B')
    this.e = this.generateEphemeral()
    // <- e (responder's ephemeral)
    this.ss.mixHash(this.e.publicKey)
    // ee
    this.ss.mixKey(x25519.getSharedSecret(this.e.privateKey, this.re))
    // se (responder side: DH(e, rs))
    this.ss.mixKey(x25519.getSharedSecret(this.e.privateKey, this.rs!))
    const payloadCipher = this.ss.encryptAndHash(payload)
    return concat(this.e.publicKey, payloadCipher)
  }

  /// Initiator reads responder's message B.
  readMessageB(message: Uint8Array): Uint8Array {
    if (!this.initiator) throw new Error('Only the initiator reads message B')
    if (message.length < DHLEN + TAGLEN) {
      throw new Error('Noise IK message B is shorter than minimum length')
    }
    let off = 0
    this.re = message.slice(off, off + DHLEN)
    off += DHLEN
    this.ss.mixHash(this.re)
    // ee
    this.ss.mixKey(x25519.getSharedSecret(this.e!.privateKey, this.re))
    // se (initiator side: DH(s, re))
    this.ss.mixKey(x25519.getSharedSecret(this.s.privateKey, this.re))
    const payloadCipher = message.slice(off)
    return this.ss.decryptAndHash(payloadCipher)
  }

  /// After both messages have been sent and read, derive the two transport
  /// CipherStates and return them keyed for this side of the handshake
  /// (send vs receive).
  finalize(): HandshakeResult {
    const [c1, c2] = this.ss.split()
    return this.initiator
      ? { send: c1, receive: c2, handshakeHash: this.ss.getHandshakeHash() }
      : { send: c2, receive: c1, handshakeHash: this.ss.getHandshakeHash() }
  }

  /// Hook so tests can inject deterministic ephemerals for known-answer
  /// vectors. Default uses crypto.getRandomValues via @noble/curves.
  protected generateEphemeral(): NoiseKeyPair {
    const priv = x25519.utils.randomPrivateKey()
    const pub = x25519.getPublicKey(priv)
    return { privateKey: priv, publicKey: pub }
  }
}

// ---- Convenience: one-call helpers ----

/// Generate a fresh X25519 keypair compatible with HandshakeState's `s` /
/// `e` shapes. Wraps the @noble/curves call so callers don't need to
/// import the underlying primitive.
export function generateNoiseKeyPair(): NoiseKeyPair {
  const priv = x25519.utils.randomPrivateKey()
  const pub = x25519.getPublicKey(priv)
  return { privateKey: priv, publicKey: pub }
}
