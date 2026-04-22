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
} from './pairing.js'
