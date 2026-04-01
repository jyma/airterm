// ---- Session types ----

export type SessionStatus = 'discovered' | 'connected' | 'active' | 'ended'

export interface SessionInfo {
  readonly id: string
  readonly name: string
  readonly cwd: string
  readonly terminal: string
  readonly status: SessionStatus
  readonly lastOutput: string
  readonly needsApproval: boolean
}

// ---- Terminal event types ----

export interface MessageEvent {
  readonly type: 'message'
  readonly text: string
}

export interface DiffHunkLine {
  readonly op: 'add' | 'remove' | 'context'
  readonly text: string
}

export interface DiffHunk {
  readonly oldStart: number
  readonly lines: readonly DiffHunkLine[]
}

export interface DiffEvent {
  readonly type: 'diff'
  readonly file: string
  readonly hunks: readonly DiffHunk[]
}

export interface ApprovalEvent {
  readonly type: 'approval'
  readonly tool: string
  readonly command: string
  readonly prompt: string
}

export interface ToolCallEvent {
  readonly type: 'tool_call'
  readonly tool: string
  readonly args: Record<string, unknown>
  readonly output?: string
}

export interface CompletionEvent {
  readonly type: 'completion'
  readonly summary: string
}

export type TerminalEvent =
  | MessageEvent
  | DiffEvent
  | ApprovalEvent
  | ToolCallEvent
  | CompletionEvent

// ---- Business messages (payload after decryption) ----

export interface SessionsMessage {
  readonly kind: 'sessions'
  readonly sessions: readonly SessionInfo[]
}

export interface OutputMessage {
  readonly kind: 'output'
  readonly sessionId: string
  readonly events: readonly TerminalEvent[]
}

export interface InputMessage {
  readonly kind: 'input'
  readonly sessionId: string
  readonly text: string
}

export type ApprovalAction = 'allow' | 'deny'

export interface ApprovalMessage {
  readonly kind: 'approval'
  readonly sessionId: string
  readonly action: ApprovalAction
}

export interface ShortcutMessage {
  readonly kind: 'shortcut'
  readonly sessionId: string
  readonly command: string
}

export interface BlockedMessage {
  readonly kind: 'blocked'
  readonly sessionId: string
  readonly reason: string
  readonly original: string
  readonly requiresMacConfirm: boolean
}

export interface PingMessage {
  readonly kind: 'ping'
}

export interface PongMessage {
  readonly kind: 'pong'
}

export interface LanInfoMessage {
  readonly kind: 'lan_info'
  readonly addresses: readonly string[]
  readonly port: number
  readonly ts: number
}

export type BusinessMessage =
  | SessionsMessage
  | OutputMessage
  | InputMessage
  | ApprovalMessage
  | ShortcutMessage
  | BlockedMessage
  | PingMessage
  | PongMessage
  | LanInfoMessage
