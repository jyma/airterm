export type {
  // Session
  SessionStatus,
  SessionInfo,
  // Terminal events
  MessageEvent,
  DiffHunkLine,
  DiffHunk,
  DiffEvent,
  ApprovalEvent,
  ToolCallEvent,
  CompletionEvent,
  TerminalEvent,
  // Business messages
  SessionsMessage,
  OutputMessage,
  InputMessage,
  ApprovalAction,
  ApprovalMessage,
  ShortcutMessage,
  BlockedMessage,
  PingMessage,
  PongMessage,
  LanInfoMessage,
  BusinessMessage,
} from './messages.js'

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
