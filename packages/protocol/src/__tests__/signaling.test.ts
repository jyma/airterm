import { describe, it, expect } from 'vitest'
import {
  createNoiseHandshakeFrame,
  createEncryptedFrame,
  isNoiseHandshakeFrame,
  isEncryptedFrame,
  encodeSignalingPayload,
  decodeSignalingPayload,
  type SignalingMessage,
  type SignalingPlainMessage,
  type WebRTCOfferMessage,
  type ICECandidateMessage,
} from '../signaling.js'

describe('Signaling Frame Builders', () => {
  it('creates a Noise handshake frame for each of the three stages', () => {
    for (const stage of [1, 2, 3] as const) {
      const frame = createNoiseHandshakeFrame(stage, 'YmFzZTY0')
      expect(frame.kind).toBe('noise')
      expect(frame.stage).toBe(stage)
      expect(frame.noisePayload).toBe('YmFzZTY0')
    }
  })

  it('creates an encrypted transport frame with the supplied seq', () => {
    const frame = createEncryptedFrame(7, 'Y2lwaGVy')
    expect(frame.kind).toBe('encrypted')
    expect(frame.seq).toBe(7)
    expect(frame.ciphertext).toBe('Y2lwaGVy')
  })
})

describe('Signaling Type Guards', () => {
  it('isNoiseHandshakeFrame narrows correctly', () => {
    const noise: SignalingMessage = createNoiseHandshakeFrame(1, 'AA==')
    const enc: SignalingMessage = createEncryptedFrame(0, 'BB==')
    expect(isNoiseHandshakeFrame(noise)).toBe(true)
    expect(isNoiseHandshakeFrame(enc)).toBe(false)
  })

  it('isEncryptedFrame narrows correctly', () => {
    const noise: SignalingMessage = createNoiseHandshakeFrame(2, 'AA==')
    const enc: SignalingMessage = createEncryptedFrame(1, 'BB==')
    expect(isEncryptedFrame(noise)).toBe(false)
    expect(isEncryptedFrame(enc)).toBe(true)
  })
})

describe('Signaling Encode / Decode Round Trip', () => {
  it('round-trips a Noise handshake frame', () => {
    const original = createNoiseHandshakeFrame(2, 'noise-bytes-base64')
    const wire = encodeSignalingPayload(original)
    const parsed = decodeSignalingPayload(wire)
    expect(parsed).toEqual(original)
  })

  it('round-trips an encrypted transport frame', () => {
    const original = createEncryptedFrame(42, 'opaque-ciphertext')
    const wire = encodeSignalingPayload(original)
    const parsed = decodeSignalingPayload(wire)
    expect(parsed).toEqual(original)
  })
})

describe('SignalingPlainMessage Shapes', () => {
  it('accepts a WebRTC offer payload', () => {
    const msg: WebRTCOfferMessage = {
      type: 'webrtc_offer',
      sdp: 'v=0\r\no=- 1 1 IN IP4 0.0.0.0\r\ns=-\r\n',
    }
    expect(msg.type).toBe('webrtc_offer')
    expect(msg.sdp).toContain('v=0')
  })

  it('accepts an ICE candidate with all optional fields', () => {
    const msg: ICECandidateMessage = {
      type: 'ice_candidate',
      candidate: 'candidate:1 1 udp 2122260223 192.168.1.5 53456 typ host',
      sdpMid: '0',
      sdpMLineIndex: 0,
    }
    expect(msg.type).toBe('ice_candidate')
    expect(msg.sdpMLineIndex).toBe(0)
  })

  it('accepts an ICE candidate with optional fields omitted', () => {
    const msg: ICECandidateMessage = {
      type: 'ice_candidate',
      candidate: 'candidate:1 1 udp 2122260223 192.168.1.5 53456 typ host',
    }
    expect(msg.sdpMid).toBeUndefined()
    expect(msg.sdpMLineIndex).toBeUndefined()
  })

  it('accepts ping / pong / bye control messages', () => {
    const ping: SignalingPlainMessage = { type: 'ping', ts: 1000 }
    const pong: SignalingPlainMessage = { type: 'pong', ts: 1001 }
    const bye: SignalingPlainMessage = { type: 'bye', reason: 'user_closed' }
    expect(ping.type).toBe('ping')
    expect(pong.type).toBe('pong')
    expect(bye.type).toBe('bye')
  })
})
