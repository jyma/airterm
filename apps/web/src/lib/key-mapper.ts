/// Browser KeyboardEvent → terminal-bytes mapper.
///
/// The Mac PTY expects raw bytes the way a hardware terminal would
/// emit them, so we have to re-synthesise the escape sequences a
/// real keyboard would: arrows as CSI cursor sequences, ctrl+letter
/// as the corresponding C0 control byte, etc. The phone's virtual
/// keyboard delivers most printable chars unchanged; modifier keys
/// arrive as separate keydowns we ignore (they only matter when
/// combined with another key).
///
/// Returns a `Uint8Array` of UTF-8 bytes ready to ship inside an
/// `InputEvent` frame, or `null` for keystrokes the terminal doesn't
/// understand.

const CSI = '\x1b['

/// Named-key → bytes table. Covers the navigation cluster + a few
/// editing keys; printable characters fall through to the default
/// `event.key` UTF-8 path.
const NAMED_KEYS: Record<string, string> = {
  Enter: '\r',
  Backspace: '\x7f',
  Tab: '\t',
  Escape: '\x1b',
  ArrowUp: `${CSI}A`,
  ArrowDown: `${CSI}B`,
  ArrowRight: `${CSI}C`,
  ArrowLeft: `${CSI}D`,
  Home: `${CSI}H`,
  End: `${CSI}F`,
  PageUp: `${CSI}5~`,
  PageDown: `${CSI}6~`,
  Delete: `${CSI}3~`,
  Insert: `${CSI}2~`,
}

export function keyToBytes(event: KeyboardEvent): Uint8Array | null {
  // Pure modifier presses (Shift / Ctrl / Alt / Meta on their own)
  // never reach the terminal as bytes — they only modify other keys.
  if (
    event.key === 'Shift' ||
    event.key === 'Control' ||
    event.key === 'Alt' ||
    event.key === 'Meta'
  ) {
    return null
  }

  // Ctrl+letter → C0 control byte (0x01..0x1A for a..z).
  if (event.ctrlKey && !event.altKey && !event.metaKey && event.key.length === 1) {
    const code = event.key.toLowerCase().charCodeAt(0)
    if (code >= 0x60 && code <= 0x7f) {
      return new Uint8Array([code & 0x1f])
    }
    // Ctrl+Space, Ctrl+@, Ctrl+[, Ctrl+\, Ctrl+] etc.
    const upperCode = event.key.toUpperCase().charCodeAt(0)
    if (upperCode >= 0x40 && upperCode <= 0x5f) {
      return new Uint8Array([upperCode & 0x1f])
    }
  }

  // Alt+letter → ESC-prefix (zsh / bash / readline meta key).
  if (event.altKey && !event.ctrlKey && !event.metaKey && event.key.length === 1) {
    return new TextEncoder().encode(`\x1b${event.key}`)
  }

  // Named navigation / editing keys.
  const named = NAMED_KEYS[event.key]
  if (named !== undefined) {
    return new TextEncoder().encode(named)
  }

  // Single printable character — UTF-8 encode and ship.
  if (event.key.length === 1) {
    return new TextEncoder().encode(event.key)
  }

  return null
}

/// Browser-safe base64 encode for `InputEventFrame.bytes`.
export function bytesToBase64(b: Uint8Array): string {
  let s = ''
  for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i])
  return btoa(s)
}
