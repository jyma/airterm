import { describe, it, expect } from 'vitest'
import type {
  PairInitRequest,
  PairInitResponse,
  PairCompleteRequest,
  PairCompleteResponse,
  PairCompletedNotification,
  QRCodePayload,
  QRCodePayloadV1,
  QRCodePayloadV2,
} from '../pairing.js'
import { isQRCodePayloadV2 } from '../pairing.js'

describe('Protocol Pairing Types', () => {
  it('creates a valid PairInitRequest', () => {
    const req: PairInitRequest = {
      macDeviceId: 'mac-123',
      macName: 'My MacBook Pro',
    }
    expect(req.macDeviceId).toBe('mac-123')
    expect(req.macName).toBe('My MacBook Pro')
  })

  it('creates a valid PairInitResponse', () => {
    const res: PairInitResponse = {
      pairId: 'pair-uuid',
      pairCode: 'A3X92K',
      expiresAt: 1234567890,
    }
    expect(res.pairCode).toHaveLength(6)
    expect(res.expiresAt).toBeGreaterThan(0)
  })

  it('creates a valid PairCompleteRequest', () => {
    const req: PairCompleteRequest = {
      pairCode: 'A3X92K',
      phoneDeviceId: 'phone-456',
      phoneName: 'iPhone',
    }
    expect(req.pairCode).toBe('A3X92K')
  })

  it('creates a valid PairCompleteResponse', () => {
    const res: PairCompleteResponse = {
      token: 'phone-token-here',
      macDeviceId: 'mac-123',
      macName: 'My MacBook Pro',
    }
    expect(res.token).toBeTruthy()
    expect(res.macDeviceId).toBe('mac-123')
  })

  it('creates a valid PairCompletedNotification', () => {
    const notif: PairCompletedNotification = {
      type: 'pair_completed',
      phoneDeviceId: 'phone-456',
      phoneName: 'iPhone',
      token: 'mac-token',
    }
    expect(notif.type).toBe('pair_completed')
  })

  it('creates a valid v1 QRCodePayload (no version, optional macPublicKey)', () => {
    const qr: QRCodePayloadV1 = {
      server: 'https://relay.airterm.dev',
      pairCode: 'A3X92K',
      macDeviceId: 'mac-123',
    }
    expect(qr.server).toContain('https')
    expect(qr.pairCode).toHaveLength(6)
    expect(isQRCodePayloadV2(qr)).toBe(false)
  })

  it('creates a valid v2 QRCodePayload with required macPublicKey', () => {
    const qr: QRCodePayloadV2 = {
      v: 2,
      server: 'https://relay.airterm.dev',
      pairCode: 'A3X92K',
      macDeviceId: 'mac-123',
      macPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    }
    expect(qr.v).toBe(2)
    expect(qr.macPublicKey.length).toBeGreaterThan(0)
    expect(isQRCodePayloadV2(qr)).toBe(true)
  })

  it('isQRCodePayloadV2 rejects v1-shaped payloads even with a publicKey', () => {
    const qr: QRCodePayload = {
      server: 'https://relay.airterm.dev',
      pairCode: 'A3X92K',
      macDeviceId: 'mac-123',
      macPublicKey: 'AAAA',
    }
    expect(isQRCodePayloadV2(qr)).toBe(false)
  })

  it('isQRCodePayloadV2 rejects v2 payloads with empty macPublicKey', () => {
    const qr = {
      v: 2,
      server: 'https://relay.airterm.dev',
      pairCode: 'A3X92K',
      macDeviceId: 'mac-123',
      macPublicKey: '',
    } as QRCodePayload
    expect(isQRCodePayloadV2(qr)).toBe(false)
  })
})
