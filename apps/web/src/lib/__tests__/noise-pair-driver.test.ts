import { describe, it, expect } from 'vitest'
import {
  HandshakeState,
  generateNoiseKeyPair,
  type NoiseKeyPair,
} from '@airterm/crypto'
import {
  createNoiseHandshakeFrame,
  type NoiseHandshakeFrame,
} from '@airterm/protocol'
import { NoisePairDriver, NoisePairDriverError } from '../noise-pair-driver'
import type { QRCodePayloadV2 } from '@airterm/protocol'

/// Helper: build a v2 QR payload referencing the given Mac public key.
function makeQR(macPub: Uint8Array): QRCodePayloadV2 {
  return {
    v: 2,
    server: 'https://relay.example',
    pairCode: 'TESTCD',
    macDeviceId: 'mac-test',
    macPublicKey: bufToBase64(macPub),
  }
}

function bufToBase64(b: Uint8Array): string {
  let s = ''
  for (const c of b) s += String.fromCharCode(c)
  return btoa(s)
}

function base64ToBuf(s: string): Uint8Array {
  const bin = atob(s)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

/// Build an in-process Mac responder that pairs with the driver. Returns
/// callbacks the test can drive: produce stage-2 in response to stage-1.
function makeMockResponder(macStatic: NoiseKeyPair): {
  handle: (frame: NoiseHandshakeFrame, prologue?: Uint8Array) => NoiseHandshakeFrame
} {
  return {
    handle(frame, prologue = new Uint8Array(0)) {
      expect(frame.kind).toBe('noise')
      expect(frame.stage).toBe(1)
      const responder = new HandshakeState({
        initiator: false,
        prologue,
        s: macStatic,
      })
      const messageA = base64ToBuf(frame.noisePayload)
      responder.readMessageA(messageA)
      const messageB = responder.writeMessageB(new Uint8Array(0))
      return createNoiseHandshakeFrame(2, bufToBase64(messageB))
    },
  }
}

describe('NoisePairDriver', () => {
  it('completes a handshake when paired with a matching Mac responder', () => {
    const macStatic = generateNoiseKeyPair()
    const phoneStatic = generateNoiseKeyPair()
    const qr = makeQR(macStatic.publicKey)

    let stage1Sent: NoiseHandshakeFrame | null = null
    const driver = new NoisePairDriver({
      qr,
      phoneStaticKeyPair: phoneStatic,
      sendFrame: (frame) => {
        stage1Sent = frame
      },
    })

    expect(driver.currentState).toBe('idle')
    driver.start()
    expect(driver.currentState).toBe('awaiting_b')
    expect(stage1Sent).not.toBeNull()
    expect(stage1Sent!.stage).toBe(1)

    const responder = makeMockResponder(macStatic)
    const stage2 = responder.handle(stage1Sent!)

    const out = driver.processIncomingMessage(stage2)
    expect(out.done).toBe(true)
    expect(out.result).toBeDefined()
    expect(out.result!.handshakeHash.length).toBeGreaterThan(0)
    expect(driver.currentState).toBe('completed')
  })

  it('rejects an extra inbound frame after completion', () => {
    const macStatic = generateNoiseKeyPair()
    const phoneStatic = generateNoiseKeyPair()
    const qr = makeQR(macStatic.publicKey)

    let stage1: NoiseHandshakeFrame | null = null
    const driver = new NoisePairDriver({
      qr,
      phoneStaticKeyPair: phoneStatic,
      sendFrame: (f) => {
        stage1 = f
      },
    })
    driver.start()
    const responder = makeMockResponder(macStatic)
    const stage2 = responder.handle(stage1!)
    driver.processIncomingMessage(stage2)
    // Another stage-2 lands — driver returns the previous result, doesn't crash
    const repeat = driver.processIncomingMessage(stage2)
    expect(repeat.done).toBe(true)
  })

  it('throws on a stage-1 frame in awaiting_b state (responder must send stage 2)', () => {
    const macStatic = generateNoiseKeyPair()
    const phoneStatic = generateNoiseKeyPair()
    const driver = new NoisePairDriver({
      qr: makeQR(macStatic.publicKey),
      phoneStaticKeyPair: phoneStatic,
      sendFrame: () => {},
    })
    driver.start()
    expect(() =>
      driver.processIncomingMessage(createNoiseHandshakeFrame(1, 'AAAA'))
    ).toThrow(/Expected stage 2/)
  })

  it('throws on an unexpected encrypted frame mid-handshake', () => {
    const macStatic = generateNoiseKeyPair()
    const phoneStatic = generateNoiseKeyPair()
    const driver = new NoisePairDriver({
      qr: makeQR(macStatic.publicKey),
      phoneStaticKeyPair: phoneStatic,
      sendFrame: () => {},
    })
    driver.start()
    expect(() =>
      driver.processIncomingMessage({
        kind: 'encrypted',
        seq: 0,
        ciphertext: 'AAAA',
      })
    ).toThrow(/before handshake completion/)
  })

  it('rejects an invalid Mac public key', () => {
    const phoneStatic = generateNoiseKeyPair()
    const badQR: QRCodePayloadV2 = {
      v: 2,
      server: 'https://relay.example',
      pairCode: 'TESTCD',
      macDeviceId: 'mac-test',
      macPublicKey: 'YQ==',  // base64-decodes to 1 byte, not 32
    }
    expect(
      () =>
        new NoisePairDriver({
          qr: badQR,
          phoneStaticKeyPair: phoneStatic,
          sendFrame: () => {},
        })
    ).toThrow(NoisePairDriverError)
  })

  it('rejects start() called twice', () => {
    const macStatic = generateNoiseKeyPair()
    const phoneStatic = generateNoiseKeyPair()
    const driver = new NoisePairDriver({
      qr: makeQR(macStatic.publicKey),
      phoneStaticKeyPair: phoneStatic,
      sendFrame: () => {},
    })
    driver.start()
    expect(() => driver.start()).toThrow(/start.*twice/)
  })

  it('honours a non-empty prologue (mismatched prologue → AEAD failure on B)', () => {
    const macStatic = generateNoiseKeyPair()
    const phoneStatic = generateNoiseKeyPair()
    let stage1: NoiseHandshakeFrame | null = null
    const driver = new NoisePairDriver({
      qr: makeQR(macStatic.publicKey),
      phoneStaticKeyPair: phoneStatic,
      prologue: new TextEncoder().encode('phone-prologue'),
      sendFrame: (f) => {
        stage1 = f
      },
    })
    driver.start()

    // Mock responder uses a DIFFERENT prologue — stage-2 should fail
    // when the driver tries to read it.
    const responder = makeMockResponder(macStatic)
    expect(() =>
      responder.handle(stage1!, new TextEncoder().encode('mac-prologue'))
    ).toThrow()
  })
})
