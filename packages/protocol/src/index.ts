export type {
  EnvelopeType,
  RelayEnvelope,
  ChallengeEnvelope,
  AuthEnvelope,
  Envelope,
  SequencedMessage,
} from './envelope.js'

export {
  createRelayEnvelope,
  createChallengeEnvelope,
  createAuthEnvelope,
  encodePayload,
  decodePayload,
} from './envelope.js'

export { ErrorCode, ErrorMessage } from './errors.js'

export type {
  PairInitRequest,
  PairInitResponse,
  PairCompleteRequest,
  PairCompleteResponse,
  PairCompletedNotification,
  QRCodePayload,
  QRCodePayloadV1,
  QRCodePayloadV2,
} from './pairing.js'

export { isQRCodePayloadV2 } from './pairing.js'

export type {
  SignalingMessage,
  NoiseHandshakeFrame,
  EncryptedFrame,
  SignalingPlainMessage,
  WebRTCOfferMessage,
  WebRTCAnswerMessage,
  ICECandidateMessage,
  PingMessage,
  PongMessage,
  ByeMessage,
} from './signaling.js'

export {
  createNoiseHandshakeFrame,
  createEncryptedFrame,
  isNoiseHandshakeFrame,
  isEncryptedFrame,
  encodeSignalingPayload,
  decodeSignalingPayload,
} from './signaling.js'
