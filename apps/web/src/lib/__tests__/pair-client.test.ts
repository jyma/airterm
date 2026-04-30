import { describe, it, expect } from 'vitest'
import { PairClientError, parseQRPayload } from '../pair-client'

describe('parseQRPayload', () => {
  it('accepts a well-formed v2 payload', () => {
    const raw = JSON.stringify({
      v: 2,
      server: 'https://relay.airterm.dev',
      pairCode: 'ABC123',
      macDeviceId: 'mac-uuid',
      macPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    })
    const parsed = parseQRPayload(raw)
    expect(parsed.v).toBe(2)
    expect(parsed.macPublicKey.length).toBeGreaterThan(0)
  })

  it('rejects non-JSON', () => {
    try {
      parseQRPayload('not json')
      throw new Error('expected throw')
    } catch (e) {
      expect(e).toBeInstanceOf(PairClientError)
      expect((e as PairClientError).code).toBe('qr_invalid_json')
    }
  })

  it('rejects v1 payloads even when macPublicKey is present', () => {
    const raw = JSON.stringify({
      server: 'https://relay.airterm.dev',
      pairCode: 'ABC123',
      macDeviceId: 'mac-uuid',
      macPublicKey: 'AAAA',
    })
    try {
      parseQRPayload(raw)
      throw new Error('expected throw')
    } catch (e) {
      expect(e).toBeInstanceOf(PairClientError)
      expect((e as PairClientError).code).toBe('qr_unsupported_version')
    }
  })

  it('rejects v2 payloads with non-http(s) server URLs', () => {
    const raw = JSON.stringify({
      v: 2,
      server: 'ftp://example.com',
      pairCode: 'ABC123',
      macDeviceId: 'mac-uuid',
      macPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    })
    try {
      parseQRPayload(raw)
      throw new Error('expected throw')
    } catch (e) {
      expect(e).toBeInstanceOf(PairClientError)
      expect((e as PairClientError).code).toBe('qr_bad_server')
    }
  })

  it('rejects v2 payloads with empty macPublicKey', () => {
    const raw = JSON.stringify({
      v: 2,
      server: 'https://relay.airterm.dev',
      pairCode: 'ABC123',
      macDeviceId: 'mac-uuid',
      macPublicKey: '',
    })
    try {
      parseQRPayload(raw)
      throw new Error('expected throw')
    } catch (e) {
      expect(e).toBeInstanceOf(PairClientError)
      expect((e as PairClientError).code).toBe('qr_unsupported_version')
    }
  })
})
