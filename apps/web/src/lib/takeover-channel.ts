import type { CipherState } from '@airterm/crypto'
import {
  decodeTakeoverFrame,
  encodeTakeoverFrame,
  type TakeoverFrame,
} from '@airterm/protocol'
import {
  createEncryptedFrame,
  type EncryptedFrame,
  type SignalingMessage,
} from '@airterm/protocol'

/// Post-handshake transport channel: pumps `TakeoverFrame`s through
/// the two `CipherState`s the Noise IK handshake produced. Pure logic
/// with IO injected — caller wires `sendSignaling` to whatever channel
/// it has (the WS during pair / takeover, a WebRTC data channel later).
///
/// Wire stack (per outbound frame):
///   TakeoverFrame
///     ↓ encodeTakeoverFrame  (JSON)
///   plaintext bytes
///     ↓ CipherState.encrypt  (ChaCha20-Poly1305 + counter nonce)
///   ciphertext bytes
///     ↓ base64
///   EncryptedFrame { kind: 'encrypted', seq, ciphertext }
///     ↓ ws-client wraps in SequencedMessage + RelayEnvelope
///
/// Inbound is the inverse, with replay rejection on the local
/// `lastIncomingSeq` counter so a relay-replayed frame is dropped.
export interface TakeoverChannelOptions {
  readonly send: CipherState
  readonly receive: CipherState
  readonly sendSignaling: (msg: SignalingMessage) => void
  readonly onFrame: (frame: TakeoverFrame) => void
  /// Caller can hook a non-fatal error (decode failure, replay, etc.)
  /// for telemetry without crashing the session.
  readonly onError?: (error: TakeoverChannelError) => void
}

export class TakeoverChannelError extends Error {
  constructor(readonly code: string, message: string) {
    super(message)
    this.name = 'TakeoverChannelError'
  }
}

const TEXT = new TextEncoder()
const TEXT_DECODE = new TextDecoder()

export class TakeoverChannel {
  private readonly send: CipherState
  private readonly receive: CipherState
  private readonly sendSignaling: (msg: SignalingMessage) => void
  private readonly onFrame: (frame: TakeoverFrame) => void
  private readonly onError: (error: TakeoverChannelError) => void
  private outboundSeq = 0
  private lastIncomingSeq = -1
  private closed = false

  constructor(opts: TakeoverChannelOptions) {
    this.send = opts.send
    this.receive = opts.receive
    this.sendSignaling = opts.sendSignaling
    this.onFrame = opts.onFrame
    this.onError = opts.onError ?? (() => {})
  }

  /// Encode + encrypt + wrap `frame` into an `EncryptedFrame`, then
  /// hand it off to the caller's signaling sink. Throws if the
  /// underlying Noise CipherState exhausts its nonce (caller MUST
  /// rekey before that point — Noise §5.1).
  sendFrame(frame: TakeoverFrame): void {
    if (this.closed) {
      throw new TakeoverChannelError('closed', 'TakeoverChannel is closed.')
    }
    const plaintext = TEXT.encode(encodeTakeoverFrame(frame))
    const ciphertext = this.send.encrypt(plaintext)
    const seq = this.outboundSeq++
    const encrypted = createEncryptedFrame(seq, bufToB64(ciphertext))
    this.sendSignaling(encrypted)
  }

  /// Feed one inbound `SignalingMessage` (already unwrapped from the
  /// `RelayEnvelope.payload` + `SequencedMessage` by the WS layer).
  /// Returns true if the message produced a frame, false if it was a
  /// non-encrypted signaling message that the channel doesn't own
  /// (the caller routes those elsewhere).
  handleIncoming(message: SignalingMessage): boolean {
    if (this.closed) return false
    if (message.kind !== 'encrypted') return false

    const frame = message as EncryptedFrame
    if (frame.seq <= this.lastIncomingSeq) {
      this.onError(new TakeoverChannelError(
        'replay',
        `Dropping replayed/out-of-order frame seq=${frame.seq} (expected > ${this.lastIncomingSeq})`
      ))
      return true
    }

    let plaintext: Uint8Array
    try {
      plaintext = this.receive.decrypt(b64ToBuf(frame.ciphertext))
    } catch (e) {
      this.onError(new TakeoverChannelError(
        'aead_failure',
        e instanceof Error ? e.message : String(e)
      ))
      return true
    }

    let decoded: TakeoverFrame
    try {
      decoded = decodeTakeoverFrame(TEXT_DECODE.decode(plaintext))
    } catch (e) {
      this.onError(new TakeoverChannelError(
        'decode_failure',
        e instanceof Error ? e.message : String(e)
      ))
      return true
    }

    this.lastIncomingSeq = frame.seq
    try {
      this.onFrame(decoded)
    } catch (e) {
      // Frame handlers shouldn't throw, but if they do we want to
      // keep the channel alive — surface via onError instead.
      this.onError(new TakeoverChannelError(
        'handler_threw',
        e instanceof Error ? e.message : String(e)
      ))
    }
    return true
  }

  close(): void {
    this.closed = true
  }

  get isClosed(): boolean {
    return this.closed
  }
}

// ---- helpers ----

function bufToB64(b: Uint8Array): string {
  let s = ''
  for (const c of b) s += String.fromCharCode(c)
  return btoa(s)
}

function b64ToBuf(s: string): Uint8Array {
  const bin = atob(s)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}
