// Takeover frames — application-layer payloads that ride inside the
// post-handshake `EncryptedFrame.ciphertext`.
//
// Phase 4 ships a JSON-over-Noise MVP: Mac encodes terminal-screen
// state into one of these frames, encrypts with the Noise transport
// `CipherState`, wraps in an `EncryptedFrame`, and sends through the
// already-paired WS relay. The phone decrypts and renders. Reverse
// direction carries `InputEvent` frames from the phone.
//
// A future Phase 4.1 will swap WS for a WebRTC data-channel transport
// without touching this schema — the channel is opaque to it.
//
// Wire format inside the Noise plaintext:
//
//   JSON.stringify({ kind: 'screen_snapshot', ... }) + UTF-8 bytes
//
// Same JSON convention the signaling layer uses; binary framing is a
// later optimisation once the v1 path is proven.

// ---- Cell + screen primitives ----

/// One terminal cell on the wire. Mirrors the subset of
/// `Services/Cell.swift::CellAttributes` the phone needs to render —
/// `bg` / `fg` are the standard 24-bit packed RGB the Mac renderer
/// already computes (`(r << 16) | (g << 8) | b`), or `null` for
/// "default-terminal-foreground/background". Nullable forms keep
/// the wire compact when the row is plain text.
export interface CellFrame {
  /// One unicode scalar value — empty string for blank cells. The
  /// phone renderer pads to one column; double-width handling is
  /// expressed by an explicit `width: 2` (default 1).
  readonly ch: string
  readonly fg?: number | null
  readonly bg?: number | null
  /// Bit-packed style flags so the wire stays small:
  ///   0x01 bold · 0x02 dim · 0x04 italic · 0x08 underline ·
  ///   0x10 reverse · 0x20 strikethrough
  readonly attrs?: number
  readonly width?: 1 | 2
}

export interface CursorFrame {
  readonly row: number
  readonly col: number
  /// True when the cursor would be drawn (not in an off-cycle blink
  /// frame). Mac sends true on every snapshot — phone may locally
  /// blink it.
  readonly visible: boolean
}

// ---- Frame variants ----

export type TakeoverFrame =
  | ScreenSnapshotFrame
  | ScreenDeltaFrame
  | InputEventFrame
  | ResizeFrame
  | PingFrame
  | ByeFrame

/// Full grid resnap. Sent on connection, on resize, or as a periodic
/// keyframe to recover from any prior packet loss / decode error.
/// `seq` is the sender's monotonic stream sequence (independent of
/// the Noise CipherState counter — that one's per-direction; this is
/// per-stream).
export interface ScreenSnapshotFrame {
  readonly kind: 'screen_snapshot'
  readonly seq: number
  readonly rows: number
  readonly cols: number
  /// `rows × cols` cells, row-major. Empty rows compress well with
  /// `ch: ''` cells; binary framing later will cut this further.
  readonly cells: ReadonlyArray<ReadonlyArray<CellFrame>>
  readonly cursor: CursorFrame
  readonly title?: string
}

/// Differential update — rewrite specified rows (full-row replacement
/// is simpler than per-cell patches and handles >90% of common
/// terminal traffic well). Caller MAY emit a snapshot any time.
export interface ScreenDeltaFrame {
  readonly kind: 'screen_delta'
  readonly seq: number
  readonly rows: ReadonlyArray<{
    readonly row: number
    readonly cells: ReadonlyArray<CellFrame>
  }>
  readonly cursor?: CursorFrame
  readonly title?: string
}

/// Phone → Mac. Caller normalises modifier-shifted keys before
/// sending — the Mac side just writes the resulting bytes to its PTY.
/// `bytes` is base64-encoded raw bytes (UTF-8 text, control codes,
/// CSI escape sequences).
export interface InputEventFrame {
  readonly kind: 'input_event'
  readonly seq: number
  readonly bytes: string
}

/// Either side requests a grid resize. Phone usually sends this on
/// orientation change / soft-keyboard show. Mac then re-runs
/// `ioctl(TIOCSWINSZ)` and SIGWINCH.
export interface ResizeFrame {
  readonly kind: 'resize'
  readonly seq: number
  readonly rows: number
  readonly cols: number
}

export interface PingFrame {
  readonly kind: 'ping'
  readonly seq: number
  readonly ts: number
}

export interface ByeFrame {
  readonly kind: 'bye'
  readonly seq: number
  readonly reason?: string
}

// ---- Type guards ----

export function isScreenSnapshotFrame(f: TakeoverFrame): f is ScreenSnapshotFrame {
  return f.kind === 'screen_snapshot'
}

export function isScreenDeltaFrame(f: TakeoverFrame): f is ScreenDeltaFrame {
  return f.kind === 'screen_delta'
}

export function isInputEventFrame(f: TakeoverFrame): f is InputEventFrame {
  return f.kind === 'input_event'
}

export function isResizeFrame(f: TakeoverFrame): f is ResizeFrame {
  return f.kind === 'resize'
}

// ---- Encode / decode helpers ----

/// JSON-encode a frame for placement inside an `EncryptedFrame`.
/// Counterpart to the signaling layer's `encodeSignalingPayload`,
/// kept separate so callers can't accidentally mix the two
/// schema spaces.
export function encodeTakeoverFrame(frame: TakeoverFrame): string {
  return JSON.stringify(frame)
}

export function decodeTakeoverFrame(text: string): TakeoverFrame {
  const obj = JSON.parse(text) as TakeoverFrame
  // Guard at the boundary: anything without a known `kind` is
  // rejected here so receivers can rely on exhaustive switching.
  switch (obj.kind) {
    case 'screen_snapshot':
    case 'screen_delta':
    case 'input_event':
    case 'resize':
    case 'ping':
    case 'bye':
      return obj
    default:
      throw new Error(`Unknown takeover frame kind: ${(obj as { kind?: string }).kind ?? '<missing>'}`)
  }
}

// ---- Style flag constants (mirror Services/Cell.swift::CellAttributes) ----

export const ATTR_BOLD          = 0x01
export const ATTR_DIM           = 0x02
export const ATTR_ITALIC        = 0x04
export const ATTR_UNDERLINE     = 0x08
export const ATTR_REVERSE       = 0x10
export const ATTR_STRIKETHROUGH = 0x20
