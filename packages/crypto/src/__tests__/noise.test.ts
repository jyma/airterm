import { describe, it, expect } from 'vitest'
import {
  HandshakeState,
  SymmetricState,
  generateNoiseKeyPair,
  NOISE_PROTOCOL_NAME,
  HASHLEN,
  DHLEN,
  TAGLEN,
} from '../noise.js'

describe('Noise SymmetricState', () => {
  it('initializes the running hash to the protocol name (≤ HASHLEN)', () => {
    const ss = new SymmetricState()
    ss.initialize(NOISE_PROTOCOL_NAME)
    expect(ss.h.length).toBe(HASHLEN)
    // First N bytes should be the UTF-8 protocol name.
    const expected = new TextEncoder().encode(NOISE_PROTOCOL_NAME)
    for (let i = 0; i < expected.length; i++) {
      expect(ss.h[i]).toBe(expected[i])
    }
  })

  it('mixKey installs a key after the first call', () => {
    const ss = new SymmetricState()
    ss.initialize(NOISE_PROTOCOL_NAME)
    expect(ss.k).toBeNull()
    ss.mixKey(new Uint8Array([1, 2, 3, 4]))
    expect(ss.k).not.toBeNull()
    expect(ss.k!.length).toBe(32)
    expect(ss.n).toBe(0n)
  })

  it('encryptAndHash with no key passes plaintext through', () => {
    const ss = new SymmetricState()
    ss.initialize(NOISE_PROTOCOL_NAME)
    const msg = new TextEncoder().encode('hello')
    const out = ss.encryptAndHash(msg)
    expect(Array.from(out)).toEqual(Array.from(msg))
  })

  it('encryptAndHash with a key produces ciphertext with TAGLEN tag', () => {
    const ss = new SymmetricState()
    ss.initialize(NOISE_PROTOCOL_NAME)
    ss.mixKey(new Uint8Array(32).fill(7))
    const msg = new TextEncoder().encode('secret')
    const out = ss.encryptAndHash(msg)
    expect(out.length).toBe(msg.length + TAGLEN)
  })

  it('decryptAndHash inverts encryptAndHash on a parallel SymmetricState', () => {
    const a = new SymmetricState()
    const b = new SymmetricState()
    a.initialize(NOISE_PROTOCOL_NAME)
    b.initialize(NOISE_PROTOCOL_NAME)
    const material = new Uint8Array(32).fill(13)
    a.mixKey(material)
    b.mixKey(material)

    const msg = new TextEncoder().encode('round-trip me')
    const cipher = a.encryptAndHash(msg)
    const recovered = b.decryptAndHash(cipher)
    expect(new TextDecoder().decode(recovered)).toBe('round-trip me')
    // Both sides should have advanced identically.
    expect(Array.from(a.h)).toEqual(Array.from(b.h))
    expect(a.n).toBe(b.n)
  })
})

describe('Noise IK Handshake (round trip)', () => {
  it('completes the full pattern and produces matching transport keys', () => {
    const responderStatic = generateNoiseKeyPair()
    const initiatorStatic = generateNoiseKeyPair()

    const initiator = new HandshakeState({
      initiator: true,
      prologue: new Uint8Array(0),
      s: initiatorStatic,
      rs: responderStatic.publicKey,
    })
    const responder = new HandshakeState({
      initiator: false,
      prologue: new Uint8Array(0),
      s: responderStatic,
    })

    const payloadA = new TextEncoder().encode('hello-from-initiator')
    const payloadB = new TextEncoder().encode('hello-from-responder')

    const messageA = initiator.writeMessageA(payloadA)
    const recoveredA = responder.readMessageA(messageA)
    expect(new TextDecoder().decode(recoveredA)).toBe('hello-from-initiator')
    // Responder must have learned the initiator's static.
    expect(responder.rs).not.toBeNull()
    expect(Array.from(responder.rs!)).toEqual(Array.from(initiatorStatic.publicKey))

    const messageB = responder.writeMessageB(payloadB)
    const recoveredB = initiator.readMessageB(messageB)
    expect(new TextDecoder().decode(recoveredB)).toBe('hello-from-responder')

    const initFinal = initiator.finalize()
    const respFinal = responder.finalize()
    // Channel-binding hashes must match exactly on both sides.
    expect(Array.from(initFinal.handshakeHash)).toEqual(Array.from(respFinal.handshakeHash))

    // Transport encryption: initiator-send + responder-receive must agree.
    const itrCipher = initFinal.send.encrypt(new TextEncoder().encode('ping-1'))
    const respPlain = respFinal.receive.decrypt(itrCipher)
    expect(new TextDecoder().decode(respPlain)).toBe('ping-1')

    // And the other direction.
    const respCipher = respFinal.send.encrypt(new TextEncoder().encode('pong-1'))
    const itrPlain = initFinal.receive.decrypt(respCipher)
    expect(new TextDecoder().decode(itrPlain)).toBe('pong-1')
  })

  it('rejects message B from the wrong role', () => {
    const responderStatic = generateNoiseKeyPair()
    const initiatorStatic = generateNoiseKeyPair()
    const initiator = new HandshakeState({
      initiator: true,
      prologue: new Uint8Array(0),
      s: initiatorStatic,
      rs: responderStatic.publicKey,
    })
    expect(() => initiator.writeMessageB(new Uint8Array())).toThrow(
      /Only the responder writes message B/
    )
  })

  it('rejects message A from the wrong role', () => {
    const responderStatic = generateNoiseKeyPair()
    const responder = new HandshakeState({
      initiator: false,
      prologue: new Uint8Array(0),
      s: responderStatic,
    })
    expect(() => responder.writeMessageA(new Uint8Array())).toThrow(
      /Only the initiator writes message A/
    )
  })

  it('detects ciphertext tampering during readMessageA', () => {
    const responderStatic = generateNoiseKeyPair()
    const initiatorStatic = generateNoiseKeyPair()
    const initiator = new HandshakeState({
      initiator: true,
      prologue: new Uint8Array(0),
      s: initiatorStatic,
      rs: responderStatic.publicKey,
    })
    const responder = new HandshakeState({
      initiator: false,
      prologue: new Uint8Array(0),
      s: responderStatic,
    })

    const messageA = initiator.writeMessageA(new TextEncoder().encode('hi'))
    // Flip a byte deep in the ciphertext (past the leading ephemeral
    // pubkey at offset 0..31 — that bit lives in the encrypted-static
    // region which is AEAD-protected).
    messageA[DHLEN + 5] ^= 0xff
    expect(() => responder.readMessageA(messageA)).toThrow()
  })

  it('honours the prologue (mismatched prologue → handshake fails)', () => {
    const responderStatic = generateNoiseKeyPair()
    const initiatorStatic = generateNoiseKeyPair()
    const initiator = new HandshakeState({
      initiator: true,
      prologue: new TextEncoder().encode('AirTerm Pair v2'),
      s: initiatorStatic,
      rs: responderStatic.publicKey,
    })
    const responder = new HandshakeState({
      initiator: false,
      prologue: new TextEncoder().encode('different prologue'),
      s: responderStatic,
    })
    const messageA = initiator.writeMessageA(new TextEncoder().encode('hi'))
    expect(() => responder.readMessageA(messageA)).toThrow()
  })

  it('rejects an initiator without rs', () => {
    expect(
      () =>
        new HandshakeState({
          initiator: true,
          prologue: new Uint8Array(0),
          s: generateNoiseKeyPair(),
        })
    ).toThrow(/responder static/)
  })
})
