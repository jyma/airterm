// ---- Envelope: outer wrapper visible to relay server ----

export type EnvelopeType = 'relay' | 'challenge' | 'auth'

export interface RelayEnvelope {
  readonly type: 'relay'
  readonly from: string
  readonly to: string
  readonly ts: number
  readonly payload: string // base64 encoded encrypted data (or plaintext JSON in MVP)
}

// ---- LAN authentication messages ----

export interface ChallengeEnvelope {
  readonly type: 'challenge'
  readonly nonce: string
}

export interface AuthEnvelope {
  readonly type: 'auth'
  readonly deviceId: string
  readonly response: string
}

export type Envelope = RelayEnvelope | ChallengeEnvelope | AuthEnvelope

// ---- Sequenced message: business message with seq/ack ----

export interface SequencedMessage<TMessage = unknown> {
  readonly seq: number
  readonly ack: number
  readonly message: TMessage
}

// ---- Envelope helpers ----

export function createRelayEnvelope(from: string, to: string, payload: string): RelayEnvelope {
  return {
    type: 'relay',
    from,
    to,
    ts: Date.now(),
    payload,
  }
}

export function createChallengeEnvelope(nonce: string): ChallengeEnvelope {
  return { type: 'challenge', nonce }
}

export function createAuthEnvelope(deviceId: string, response: string): AuthEnvelope {
  return { type: 'auth', deviceId, response }
}

// ---- Serialization helpers (MVP: plaintext JSON) ----

export function encodePayload<T>(msg: SequencedMessage<T>): string {
  return btoa(JSON.stringify(msg))
}

export function decodePayload<T = unknown>(payload: string): SequencedMessage<T> {
  return JSON.parse(atob(payload)) as SequencedMessage<T>
}
