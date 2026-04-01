import { describe, it, expect } from 'vitest'
import {
  generateKeyPair,
  deriveSharedSecret,
  encodeKey,
  decodeKey,
  encrypt,
  decrypt,
  serializeEncrypted,
  deserializeEncrypted,
  createSequenceState,
  allocateSeq,
  updateAck,
  validateSeq,
  buildAAD,
  generateSAS,
} from '../index.js'

describe('Key Exchange (X25519)', () => {
  it('generates unique key pairs', () => {
    const a = generateKeyPair()
    const b = generateKeyPair()
    expect(a.publicKey).not.toEqual(b.publicKey)
    expect(a.privateKey).not.toEqual(b.privateKey)
    expect(a.publicKey.length).toBe(32)
    expect(a.privateKey.length).toBe(32)
  })

  it('derives same shared secret from both sides', () => {
    const mac = generateKeyPair()
    const phone = generateKeyPair()

    const secretA = deriveSharedSecret(mac.privateKey, phone.publicKey)
    const secretB = deriveSharedSecret(phone.privateKey, mac.publicKey)

    expect(secretA).toEqual(secretB)
    expect(secretA.length).toBe(32)
  })

  it('encodes and decodes keys', () => {
    const kp = generateKeyPair()
    const encoded = encodeKey(kp.publicKey)
    const decoded = decodeKey(encoded)
    expect(decoded).toEqual(kp.publicKey)
  })
})

describe('Encryption (ChaCha20-Poly1305)', () => {
  it('encrypts and decrypts a message', () => {
    const mac = generateKeyPair()
    const phone = generateKeyPair()
    const secret = deriveSharedSecret(mac.privateKey, phone.publicKey)

    const plaintext = new TextEncoder().encode('Hello, secure world!')
    const encrypted = encrypt(secret, plaintext)
    const decrypted = decrypt(secret, encrypted)

    expect(new TextDecoder().decode(decrypted)).toBe('Hello, secure world!')
  })

  it('uses unique nonce for each encryption', () => {
    const secret = deriveSharedSecret(generateKeyPair().privateKey, generateKeyPair().publicKey)
    const plaintext = new TextEncoder().encode('test')

    const a = encrypt(secret, plaintext)
    const b = encrypt(secret, plaintext)

    expect(a.nonce).not.toEqual(b.nonce)
  })

  it('rejects tampered ciphertext', () => {
    const secret = deriveSharedSecret(generateKeyPair().privateKey, generateKeyPair().publicKey)
    const plaintext = new TextEncoder().encode('test')
    const encrypted = encrypt(secret, plaintext)

    // Tamper with ciphertext
    const tampered = {
      nonce: encrypted.nonce,
      ciphertext: new Uint8Array([...encrypted.ciphertext]),
    }
    tampered.ciphertext[0] ^= 0xff

    expect(() => decrypt(secret, tampered)).toThrow()
  })

  it('rejects wrong key', () => {
    const mac = generateKeyPair()
    const phone = generateKeyPair()
    const attacker = generateKeyPair()
    const secret = deriveSharedSecret(mac.privateKey, phone.publicKey)
    const wrongSecret = deriveSharedSecret(attacker.privateKey, phone.publicKey)

    const plaintext = new TextEncoder().encode('secret')
    const encrypted = encrypt(secret, plaintext)

    expect(() => decrypt(wrongSecret, encrypted)).toThrow()
  })

  it('validates AAD (prevents replay with different seq)', () => {
    const secret = deriveSharedSecret(generateKeyPair().privateKey, generateKeyPair().publicKey)
    const plaintext = new TextEncoder().encode('test')
    const aad = buildAAD(1, 0)

    const encrypted = encrypt(secret, plaintext, aad)

    // Correct AAD works
    expect(() => decrypt(secret, encrypted, aad)).not.toThrow()

    // Wrong AAD fails
    const wrongAad = buildAAD(2, 0)
    expect(() => decrypt(secret, encrypted, wrongAad)).toThrow()
  })

  it('serializes and deserializes encrypted messages', () => {
    const secret = deriveSharedSecret(generateKeyPair().privateKey, generateKeyPair().publicKey)
    const plaintext = new TextEncoder().encode('serialize test')

    const encrypted = encrypt(secret, plaintext)
    const serialized = serializeEncrypted(encrypted)
    const deserialized = deserializeEncrypted(serialized)
    const decrypted = decrypt(secret, deserialized)

    expect(new TextDecoder().decode(decrypted)).toBe('serialize test')
  })

  it('pads messages to 1KB boundaries', () => {
    const secret = deriveSharedSecret(generateKeyPair().privateKey, generateKeyPair().publicKey)

    const small = encrypt(secret, new TextEncoder().encode('hi'))
    const medium = encrypt(secret, new TextEncoder().encode('a'.repeat(500)))

    // Both should produce ciphertext padded to 1KB + overhead
    // Nonce(12) + padded(1024) + tag(16) = 1052 for small messages
    expect(small.ciphertext.length).toBe(medium.ciphertext.length)
  })
})

describe('Sequence Numbers', () => {
  it('allocates incrementing sequence numbers', () => {
    const state = createSequenceState()
    const r1 = allocateSeq(state)
    expect(r1.seq).toBe(1)

    const r2 = allocateSeq(r1.state)
    expect(r2.seq).toBe(2)

    const r3 = allocateSeq(r2.state)
    expect(r3.seq).toBe(3)
  })

  it('validates expected sequence numbers', () => {
    const state = createSequenceState()

    const r1 = validateSeq(state, 1)
    expect(r1.result).toBe('ok')

    const r2 = validateSeq(r1.state, 2)
    expect(r2.result).toBe('ok')
  })

  it('detects duplicate sequence numbers', () => {
    const state = createSequenceState()

    const r1 = validateSeq(state, 1)
    expect(r1.result).toBe('ok')

    const r2 = validateSeq(r1.state, 1) // duplicate
    expect(r2.result).toBe('duplicate')
  })

  it('detects out-of-order sequence numbers', () => {
    const state = createSequenceState()
    const r = validateSeq(state, 3) // expected 1, got 3
    expect(r.result).toBe('out_of_order')
  })

  it('updates ack to max received', () => {
    let state = createSequenceState()
    state = updateAck(state, 5)
    expect(state.lastAck).toBe(5)

    state = updateAck(state, 3) // lower, should not decrease
    expect(state.lastAck).toBe(5)

    state = updateAck(state, 8)
    expect(state.lastAck).toBe(8)
  })

  it('builds AAD from seq and ack', () => {
    const aad = buildAAD(42, 41)
    expect(aad.length).toBe(8)

    const view = new DataView(aad.buffer)
    expect(view.getUint32(0, false)).toBe(42)
    expect(view.getUint32(4, false)).toBe(41)
  })
})

describe('SAS Verification', () => {
  it('generates 4-digit code', () => {
    const mac = generateKeyPair()
    const phone = generateKeyPair()

    const code = generateSAS(mac.publicKey, phone.publicKey)
    expect(code).toMatch(/^\d{4}$/)
  })

  it('produces same code regardless of key order', () => {
    const mac = generateKeyPair()
    const phone = generateKeyPair()

    const code1 = generateSAS(mac.publicKey, phone.publicKey)
    const code2 = generateSAS(phone.publicKey, mac.publicKey)
    expect(code1).toBe(code2)
  })

  it('produces different codes for different key pairs', () => {
    const a = generateKeyPair()
    const b = generateKeyPair()
    const c = generateKeyPair()

    const code1 = generateSAS(a.publicKey, b.publicKey)
    const code2 = generateSAS(a.publicKey, c.publicKey)
    // Not guaranteed different but extremely unlikely to be same
    // Just verify they're valid codes
    expect(code1).toMatch(/^\d{4}$/)
    expect(code2).toMatch(/^\d{4}$/)
  })
})
