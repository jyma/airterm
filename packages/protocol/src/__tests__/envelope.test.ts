import { describe, it, expect } from 'vitest'
import {
  createRelayEnvelope,
  createChallengeEnvelope,
  createAuthEnvelope,
  encodePayload,
  decodePayload,
} from '../envelope.js'
import type { SequencedMessage } from '../envelope.js'

describe('createRelayEnvelope', () => {
  it('creates a relay envelope with timestamp', () => {
    const env = createRelayEnvelope('mac-1', 'phone-1', 'encrypted-data')

    expect(env.type).toBe('relay')
    expect(env.from).toBe('mac-1')
    expect(env.to).toBe('phone-1')
    expect(env.payload).toBe('encrypted-data')
    expect(env.ts).toBeGreaterThan(0)
  })
})

describe('createChallengeEnvelope', () => {
  it('creates a challenge envelope', () => {
    const env = createChallengeEnvelope('random-nonce-hex')

    expect(env.type).toBe('challenge')
    expect(env.nonce).toBe('random-nonce-hex')
  })
})

describe('createAuthEnvelope', () => {
  it('creates an auth envelope', () => {
    const env = createAuthEnvelope('phone-1', 'hmac-response')

    expect(env.type).toBe('auth')
    expect(env.deviceId).toBe('phone-1')
    expect(env.response).toBe('hmac-response')
  })
})

describe('encodePayload / decodePayload', () => {
  it('round-trips a sequenced message', () => {
    const msg: SequencedMessage = {
      seq: 42,
      ack: 41,
      message: {
        kind: 'input',
        sessionId: 'sess_1',
        text: 'hello',
      },
    }

    const encoded = encodePayload(msg)
    expect(typeof encoded).toBe('string')

    const decoded = decodePayload(encoded)
    expect(decoded).toEqual(msg)
  })

  it('encodes to base64 string', () => {
    const msg: SequencedMessage = {
      seq: 1,
      ack: 0,
      message: { kind: 'ping' },
    }

    const encoded = encodePayload(msg)
    // Should be valid base64
    expect(() => atob(encoded)).not.toThrow()
  })
})
