import { useState } from 'react'
import { bytesToBase64 } from '../lib/key-mapper'
import type { TakeoverChannel } from '../lib/takeover-channel'

/// Sticky bar of terminal-control keys that physical phone keyboards
/// don't expose: Esc, Tab, Ctrl latch, four arrows. Sits above the
/// soft keyboard so a user running vim / htop on the Mac can actually
/// drive it from a phone.
///
/// `Ctrl` is a latch — tap once to arm, the next character emits as
/// the corresponding C0 control byte, then the latch auto-releases.
/// Long-press behaviour (sticky-Ctrl) is left for a later polish
/// pass; arming once per keystroke is the minimum that makes
/// `Ctrl-C` / `Ctrl-D` reachable.
interface MobileKeyToolbarProps {
  readonly channel: TakeoverChannel
  /// Caller increments this on every dispatch so the parent can
  /// surface a "keys out" diagnostic count.
  readonly onSend: () => void
  /// Set when the user taps Ctrl. Parent uses it to drive a visual
  /// "Ctrl armed" indicator on the next character key.
  readonly ctrlArmed: boolean
  readonly onCtrlArmedChange: (armed: boolean) => void
}

export function MobileKeyToolbar({
  channel,
  onSend,
  ctrlArmed,
  onCtrlArmedChange,
}: MobileKeyToolbarProps) {
  const sendBytes = (bytes: Uint8Array): void => {
    try {
      channel.sendFrame({
        kind: 'input_event',
        seq: outboundSeq++,
        bytes: bytesToBase64(bytes),
      })
      onSend()
    } catch {
      // Channel closed — UI route will handle the unmount.
    }
  }

  return (
    <div style={toolbarStyle} role="toolbar" aria-label="Terminal control keys">
      <Key label="Esc" onPress={() => sendBytes(BYTE_ESC)} />
      <Key label="Tab" onPress={() => sendBytes(BYTE_TAB)} />
      <Key
        label="Ctrl"
        toggled={ctrlArmed}
        onPress={() => onCtrlArmedChange(!ctrlArmed)}
      />
      <Spacer />
      <Key label="←" onPress={() => sendBytes(BYTE_LEFT)} />
      <Key label="↓" onPress={() => sendBytes(BYTE_DOWN)} />
      <Key label="↑" onPress={() => sendBytes(BYTE_UP)} />
      <Key label="→" onPress={() => sendBytes(BYTE_RIGHT)} />
    </div>
  )
}

interface KeyProps {
  readonly label: string
  readonly onPress: () => void
  readonly toggled?: boolean
}

function Key({ label, onPress, toggled }: KeyProps) {
  const [pressed, setPressed] = useState(false)
  return (
    <button
      type="button"
      onPointerDown={(e) => {
        // preventDefault so the focus on the input field below isn't
        // stolen — keeps the soft keyboard open through the press.
        e.preventDefault()
        setPressed(true)
      }}
      onPointerUp={() => {
        setPressed(false)
        onPress()
      }}
      onPointerCancel={() => setPressed(false)}
      style={{
        ...keyStyle,
        background: toggled
          ? 'var(--color-accent-blue)'
          : pressed
            ? 'var(--color-bg-tertiary)'
            : 'var(--color-bg-secondary)',
        color: toggled ? 'white' : 'var(--color-text-primary)',
        fontWeight: toggled ? 600 : 500,
      }}
      aria-pressed={toggled ? 'true' : undefined}
    >
      {label}
    </button>
  )
}

function Spacer() {
  return <div style={{ flex: 1 }} aria-hidden />
}

// ---- Byte sequences for terminal control keys ----

const BYTE_ESC = new Uint8Array([0x1b])
const BYTE_TAB = new Uint8Array([0x09])
const ENC = new TextEncoder()
const BYTE_UP    = ENC.encode('\x1b[A')
const BYTE_DOWN  = ENC.encode('\x1b[B')
const BYTE_RIGHT = ENC.encode('\x1b[C')
const BYTE_LEFT  = ENC.encode('\x1b[D')

let outboundSeq = 0

// ---- styles ----

const toolbarStyle: React.CSSProperties = {
  display: 'flex',
  gap: 6,
  padding: 8,
  background: 'var(--color-bg-overlay)',
  borderTop: '1px solid var(--color-border)',
  position: 'sticky',
  bottom: 0,
  // iOS Safari pads the bottom for the home indicator; respect it
  // so the row sits flush above the gesture area.
  paddingBottom: 'calc(8px + env(safe-area-inset-bottom))',
  zIndex: 10,
}

const keyStyle: React.CSSProperties = {
  flex: '0 0 auto',
  minWidth: 44,
  height: 36,
  border: '1px solid var(--color-border)',
  borderRadius: 8,
  fontSize: 14,
  fontFamily: 'var(--font-mono)',
  cursor: 'pointer',
  // Avoid the iOS Safari double-tap-to-zoom heuristic.
  touchAction: 'manipulation',
  // Stops "tap highlight" overlay on Safari.
  WebkitTapHighlightColor: 'transparent',
  userSelect: 'none',
  WebkitUserSelect: 'none',
}
