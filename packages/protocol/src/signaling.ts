// ---- Signaling messages exchanged inside RelayEnvelope.payload ----
//
// After a pair-init / pair-complete HTTP handshake hands both endpoints a JWT
// and binds them as a paired (mac, phone) tuple, the relay server becomes a
// dumb forwarder. Everything below rides inside the opaque base64 `payload`
// of a `RelayEnvelope` and is never inspected by the server.
//
// The pipeline has two stages, in order:
//   1. **Noise IK handshake** — three frames (`stage: 1 | 2 | 3`) carrying
//      raw Noise output. Stage 1 + 2 are the standard IK two-message pattern;
//      stage 3 is a lightweight ACK so the initiator knows the responder
//      finished installing the transport keys before the first encrypted
//      message arrives. Phone is the initiator (it scans the Mac's static
//      public key from the QR), Mac is the responder.
//   2. **Encrypted transport frames** — Noise-encrypted payloads carrying
//      WebRTC signaling (SDP offer/answer, ICE candidates) and lightweight
//      keep-alives. Each frame carries a monotonic `seq` so receivers can
//      reject replays / out-of-order delivery.
//
// Wire format: each `SignalingMessage` is JSON-stringified and then base64-
// encoded into the envelope's `payload`. Receivers do the inverse.

export type SignalingMessage = NoiseHandshakeFrame | EncryptedFrame

/// One of the three Noise IK handshake frames. `noisePayload` is the Noise
/// frame's bytes (handshake_message + optional payload), base64-encoded.
export interface NoiseHandshakeFrame {
  readonly kind: 'noise'
  readonly stage: 1 | 2 | 3
  readonly noisePayload: string
}

/// Post-handshake transport frame. `seq` starts at 0 and increments by 1 per
/// frame, per direction. `ciphertext` is base64-encoded Noise transport-
/// message bytes whose plaintext decodes to a `SignalingPlainMessage`.
export interface EncryptedFrame {
  readonly kind: 'encrypted'
  readonly seq: number
  readonly ciphertext: string
}

// ---- Plaintext messages carried inside an EncryptedFrame ----

export type SignalingPlainMessage =
  | WebRTCOfferMessage
  | WebRTCAnswerMessage
  | ICECandidateMessage
  | PingMessage
  | PongMessage
  | ByeMessage

export interface WebRTCOfferMessage {
  readonly type: 'webrtc_offer'
  readonly sdp: string
}

export interface WebRTCAnswerMessage {
  readonly type: 'webrtc_answer'
  readonly sdp: string
}

/// One ICE candidate. `candidate` is the candidate-attribute line as emitted
/// by the WebRTC peer connection. `sdpMid` and `sdpMLineIndex` follow the
/// WebRTC spec's RTCIceCandidateInit shape.
export interface ICECandidateMessage {
  readonly type: 'ice_candidate'
  readonly candidate: string
  readonly sdpMid?: string
  readonly sdpMLineIndex?: number
}

export interface PingMessage {
  readonly type: 'ping'
  readonly ts: number
}

export interface PongMessage {
  readonly type: 'pong'
  readonly ts: number
}

/// Either side announces the channel is closing. After sending `bye`,
/// senders MUST NOT send further frames. Receivers SHOULD tear down the
/// peer connection.
export interface ByeMessage {
  readonly type: 'bye'
  readonly reason?: string
}

// ---- Builders / type guards ----

export function createNoiseHandshakeFrame(
  stage: 1 | 2 | 3,
  noisePayload: string
): NoiseHandshakeFrame {
  return { kind: 'noise', stage, noisePayload }
}

export function createEncryptedFrame(seq: number, ciphertext: string): EncryptedFrame {
  return { kind: 'encrypted', seq, ciphertext }
}

export function isNoiseHandshakeFrame(msg: SignalingMessage): msg is NoiseHandshakeFrame {
  return msg.kind === 'noise'
}

export function isEncryptedFrame(msg: SignalingMessage): msg is EncryptedFrame {
  return msg.kind === 'encrypted'
}

// ---- Encoding helpers ----
//
// Symmetrical with envelope.encodePayload but without the SequencedMessage
// wrapper — signaling frames carry their own sequence number where it
// matters (in EncryptedFrame), and the handshake frames are inherently
// ordered by the Noise pattern.

export function encodeSignalingPayload(msg: SignalingMessage): string {
  return btoa(JSON.stringify(msg))
}

export function decodeSignalingPayload(payload: string): SignalingMessage {
  return JSON.parse(atob(payload)) as SignalingMessage
}
