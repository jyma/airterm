import type { SequencedMessage, SignalingMessage } from '@airterm/protocol'
import type { NoiseKeyPair } from '@airterm/crypto'
import { NoisePairDriver, NoisePairDriverError } from './noise-pair-driver'
import { loadOrCreatePhoneIdentity } from './phone-identity'
import { createWSClient, type ConnectionState, type WSClient } from './ws-client'
import type { PairingInfo } from './storage'
import { TakeoverChannel } from './takeover-channel'
import { wsURLFor } from './pair-flow'

/// Long-lived connection state machine that survives WS flaps.
///
/// `runPhonePairFlow` / `runPhoneReconnectFlow` are one-shot — they
/// resolve once on success and have no story for "Mac quits and comes
/// back five minutes later". The TakeoverChannel they hand back has
/// counter-based AEAD nonces tied to the just-completed handshake;
/// when ws-client transparently reopens its WebSocket after a server
/// restart, the *server-side* state machine has nothing to feed those
/// counters and every encrypted frame fails AEAD.
///
/// The right answer is to run a fresh Noise IK handshake on every
/// `connected` transition. ConnectionManager does exactly that:
///
///   • Subscribes to the WSClient's state changes.
///   • On `connected`, spins up a NoisePairDriver and walks the IK
///     pattern again with the same persistent phone identity + the
///     stored Mac static.
///   • On Noise success, builds a new TakeoverChannel and surfaces
///     it via `onChannelChange`. The previous channel is dropped —
///     the page swap-mounts a fresh TakeoverViewer behind it.
///   • On `disconnected`, drops the channel + tells the page so the
///     UI flips to "Reconnecting…" while ws-client retries internally.
///
/// State diagram (callers also receive these strings via
/// `onStateChange`):
///
///   start()
///     ↓
///   'connecting'
///     ↓ ws onopen
///   'handshaking'
///     ↓ Noise stage 2 OK
///   'live'   ←──┐ ws reopens
///     │ ws drops │
///     ↓          │
///   'disconnected' ─┘
///
///   any IK / decode failure → 'failed' (terminal until stop())
export type ConnState =
  | 'connecting'
  | 'handshaking'
  | 'live'
  | 'disconnected'
  | 'failed'

export interface ConnectionManagerOptions {
  readonly stored: PairingInfo
  readonly onStateChange: (state: ConnState) => void
  readonly onChannelChange: (channel: TakeoverChannel | null) => void
  readonly onError?: (error: Error) => void
}

export class ConnectionManager {
  private readonly opts: ConnectionManagerOptions
  private ws: WSClient | null = null
  private driver: NoisePairDriver | null = null
  private channel: TakeoverChannel | null = null
  private phoneIdentity: NoiseKeyPair | null = null
  private state: ConnState = 'connecting'
  private stopped = false

  constructor(opts: ConnectionManagerOptions) {
    this.opts = opts
  }

  async start(): Promise<void> {
    if (!this.opts.stored.macPublicKey) {
      this.setState('failed')
      this.opts.onError?.(new Error('Stored pairing has no macPublicKey'))
      return
    }
    try {
      const identity = await loadOrCreatePhoneIdentity()
      this.phoneIdentity = identity.keyPair
    } catch (e) {
      this.setState('failed')
      this.opts.onError?.(e as Error)
      return
    }
    this.openWebSocket()
  }

  stop(): void {
    this.stopped = true
    try { this.ws?.disconnect() } catch { /* may not be open */ }
    this.ws = null
    this.driver = null
    if (this.channel) {
      this.channel.close()
      this.channel = null
      this.opts.onChannelChange(null)
    }
    this.setState('disconnected')
  }

  // MARK: - WS lifecycle

  private openWebSocket(): void {
    if (this.stopped) return
    this.setState('connecting')
    const stored = this.opts.stored
    const ws = createWSClient({
      url: wsURLFor(stored.serverUrl, 'phone'),
      token: stored.token,
      deviceId: stored.deviceId,
      targetDeviceId: stored.targetDeviceId,
      onStateChange: (s) => this.handleWsState(s),
      onMessage: (msg) => this.handleWsMessage(msg),
    })
    this.ws = ws
    ws.connect()
  }

  private handleWsState(s: ConnectionState): void {
    if (this.stopped) return
    switch (s) {
      case 'connecting':
        // Either a fresh dial or a reconnect attempt — drop any old
        // channel so the UI flips to a "Reconnecting…" state.
        this.dropChannel()
        this.setState('connecting')
        break
      case 'connected':
        // Every connected transition runs a brand-new IK handshake.
        // The Mac side's PairingCoordinator is listening for exactly
        // this on its own WS slot.
        this.startHandshake()
        break
      case 'disconnected':
        this.dropChannel()
        this.setState('disconnected')
        // ws-client schedules its own reconnect; we'll get
        // 'connecting' → 'connected' again automatically.
        break
    }
  }

  private dropChannel(): void {
    if (this.channel) {
      this.channel.close()
      this.channel = null
      this.opts.onChannelChange(null)
    }
    this.driver = null
  }

  // MARK: - Noise handshake

  private startHandshake(): void {
    if (this.stopped) return
    if (!this.phoneIdentity || !this.ws || !this.opts.stored.macPublicKey) {
      this.setState('failed')
      return
    }
    this.setState('handshaking')
    try {
      const ws = this.ws
      const driver = new NoisePairDriver({
        qr: {
          v: 2,
          server: this.opts.stored.serverUrl,
          pairCode: '',
          macDeviceId: this.opts.stored.targetDeviceId,
          macPublicKey: this.opts.stored.macPublicKey,
        },
        phoneStaticKeyPair: this.phoneIdentity,
        sendFrame: (frame) => ws.send(frame as SignalingMessage),
      })
      driver.start()
      this.driver = driver
    } catch (e) {
      this.setState('failed')
      this.opts.onError?.(e as Error)
    }
  }

  private handleWsMessage(sequenced: SequencedMessage): void {
    if (this.stopped) return
    const inner = sequenced.message as SignalingMessage
    if (this.channel && this.channel.handleIncoming(inner)) return
    if (!this.driver) return
    try {
      const out = this.driver.processIncomingMessage(inner)
      if (out.done && out.result) {
        const ws = this.ws
        if (!ws) return
        const channel = new TakeoverChannel({
          send: out.result.send,
          receive: out.result.receive,
          sendSignaling: (msg) => ws.send(msg as SignalingMessage),
          // Default no-ops; the page installs real handlers when it
          // receives the channel via onChannelChange.
          onFrame: () => {},
          onError: () => {},
        })
        this.channel = channel
        this.driver = null
        this.setState('live')
        this.opts.onChannelChange(channel)
      }
    } catch (e) {
      this.setState('failed')
      this.opts.onError?.(
        e instanceof NoisePairDriverError
          ? e
          : new Error(e instanceof Error ? e.message : String(e))
      )
    }
  }

  private setState(s: ConnState): void {
    if (this.state === s) return
    this.state = s
    this.opts.onStateChange(s)
  }
}
