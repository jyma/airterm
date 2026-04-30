import {
  HandshakeState,
  type HandshakeResult,
  type NoiseKeyPair,
} from '@airterm/crypto'
import {
  type NoiseHandshakeFrame,
  createNoiseHandshakeFrame,
  isNoiseHandshakeFrame,
  type SignalingMessage,
} from '@airterm/protocol'
import type { QRCodePayloadV2 } from '@airterm/protocol'

/// Drives the *phone side* of the Noise IK pairing handshake.
///
/// Pure logic with IO injected — the caller wires the `sendFrame`
/// callback into whatever channel it has (the WS relay during pair
/// flow, a local pipe in tests). The driver owns nothing async; every
/// operation either returns synchronously or throws. WebSocket
/// orchestration is the caller's concern, which keeps this file
/// trivially testable in vitest without spinning up a relay.
///
/// Lifecycle:
///   1. `new NoisePairDriver({...})` builds the IK initiator with the
///      phone's static keypair and the Mac's static (from the QR).
///   2. `start()` runs `writeMessageA`, hands the frame to `sendFrame`,
///      and returns. The driver is now waiting for stage 2.
///   3. The caller delivers each inbound `SignalingMessage` to
///      `processIncomingMessage`. When the responder's stage-2 frame
///      arrives, the driver finalises and returns the transport
///      `HandshakeResult` (send + receive `CipherState`s + handshake
///      hash for channel binding).
///   4. After completion, further inbound frames are rejected — the
///      transport CipherStates own all post-handshake AEAD.
export interface NoisePairDriverOptions {
  readonly qr: QRCodePayloadV2
  readonly phoneStaticKeyPair: NoiseKeyPair
  readonly sendFrame: (frame: NoiseHandshakeFrame) => void
  /// Optional bytes mixed into the SymmetricState's running hash before
  /// any keying. Both ends must use the same prologue or the AEAD on
  /// the very first frame fails. Recommended: `qrPayloadAsBytes` so
  /// the handshake binds to the exact QR the phone scanned.
  readonly prologue?: Uint8Array
  /// Optional handshake-time payload sent inside message A under
  /// AEAD. Fits things the responder needs before the Noise channel is
  /// fully open (e.g. a phone-name string). Empty by default.
  readonly handshakePayloadA?: Uint8Array
}

export type NoisePairState = 'idle' | 'awaiting_b' | 'completed' | 'failed'

export class NoisePairDriverError extends Error {
  constructor(readonly code: string, message: string) {
    super(message)
    this.name = 'NoisePairDriverError'
  }
}

export class NoisePairDriver {
  private readonly handshake: HandshakeState
  private readonly sendFrame: (frame: NoiseHandshakeFrame) => void
  private readonly handshakePayloadA: Uint8Array
  private state: NoisePairState = 'idle'
  private finalResult: HandshakeResult | null = null
  private payloadFromB: Uint8Array | null = null

  constructor(opts: NoisePairDriverOptions) {
    const rs = decodeBase64(opts.qr.macPublicKey)
    if (rs.length !== 32) {
      throw new NoisePairDriverError(
        'bad_mac_public_key',
        `Mac public key must decode to 32 bytes (got ${rs.length}).`
      )
    }
    this.handshake = new HandshakeState({
      initiator: true,
      prologue: opts.prologue ?? new Uint8Array(0),
      s: opts.phoneStaticKeyPair,
      rs,
    })
    this.sendFrame = opts.sendFrame
    this.handshakePayloadA = opts.handshakePayloadA ?? new Uint8Array(0)
  }

  /// Produce stage 1 (initiator → responder) and hand it to the
  /// caller's transport. Idempotent at the constructor level — calling
  /// `start()` twice throws.
  start(): void {
    if (this.state !== 'idle') {
      throw new NoisePairDriverError(
        'already_started',
        'NoisePairDriver.start() called twice.'
      )
    }
    let messageA: Uint8Array
    try {
      messageA = this.handshake.writeMessageA(this.handshakePayloadA)
    } catch (e) {
      this.state = 'failed'
      throw wrap(e, 'write_message_a_failed', 'Could not write Noise message A.')
    }
    this.sendFrame(createNoiseHandshakeFrame(1, encodeBase64(messageA)))
    this.state = 'awaiting_b'
  }

  /// Feed one inbound `SignalingMessage` from the relay. Returns
  /// `{ done: true, result }` when the handshake completes, `{ done: false }`
  /// if the message wasn't a stage-2 Noise frame, and throws on any
  /// protocol violation (wrong stage, AEAD failure, etc.). Callers should
  /// stop forwarding to this method once `done: true` is returned.
  processIncomingMessage(msg: SignalingMessage): { done: boolean; result?: HandshakeResult; payload?: Uint8Array } {
    if (this.state === 'completed' && this.finalResult) {
      return { done: true, result: this.finalResult, payload: this.payloadFromB ?? undefined }
    }
    if (this.state !== 'awaiting_b') {
      throw new NoisePairDriverError(
        'wrong_state',
        `Driver got an inbound frame in state ${this.state}.`
      )
    }
    if (!isNoiseHandshakeFrame(msg)) {
      // Encrypted frame arrived before handshake completion — refuse.
      throw new NoisePairDriverError(
        'unexpected_encrypted_frame',
        'Encrypted frame received before handshake completion.'
      )
    }
    if (msg.stage !== 2) {
      throw new NoisePairDriverError(
        'unexpected_stage',
        `Expected stage 2 from responder, got ${msg.stage}.`
      )
    }
    let messageB: Uint8Array
    try {
      messageB = decodeBase64(msg.noisePayload)
    } catch {
      this.state = 'failed'
      throw new NoisePairDriverError(
        'bad_base64',
        'Stage-2 noisePayload was not valid base64.'
      )
    }
    let payload: Uint8Array
    try {
      payload = this.handshake.readMessageB(messageB)
    } catch (e) {
      this.state = 'failed'
      throw wrap(e, 'read_message_b_failed', 'Could not read Noise message B.')
    }
    this.finalResult = this.handshake.finalize()
    this.payloadFromB = payload
    this.state = 'completed'
    return { done: true, result: this.finalResult, payload }
  }

  get currentState(): NoisePairState {
    return this.state
  }
}

// ---- helpers ----

function decodeBase64(s: string): Uint8Array {
  // browser-safe base64 → bytes
  const bin = atob(s)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

function encodeBase64(bytes: Uint8Array): string {
  let s = ''
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i])
  return btoa(s)
}

function wrap(error: unknown, code: string, message: string): NoisePairDriverError {
  if (error instanceof NoisePairDriverError) return error
  const detail = error instanceof Error ? error.message : String(error)
  return new NoisePairDriverError(code, `${message} (${detail})`)
}
