import type { ConnState } from '../lib/connection-manager'

/// Small status chip shown in the takeover header. Colour + label
/// reflect the connection-manager state so users always know whether
/// they're seeing a frozen image or a live mirror.
interface ConnectionPillProps {
  readonly state: ConnState
}

export function ConnectionPill({ state }: ConnectionPillProps) {
  const { label, color, dot, blink } = describe(state)
  return (
    <span style={pillStyle(color)} role="status" aria-live="polite">
      <span style={dotStyle(dot, blink)} aria-hidden />
      {label}
    </span>
  )
}

function describe(state: ConnState): {
  label: string
  color: string
  dot: string
  blink: boolean
} {
  switch (state) {
    case 'connecting':
      return { label: 'Connecting', color: 'var(--color-text-secondary)', dot: 'var(--color-accent-yellow)', blink: true }
    case 'handshaking':
      return { label: 'Securing', color: 'var(--color-text-secondary)', dot: 'var(--color-accent-blue)', blink: true }
    case 'live':
      return { label: 'Live', color: 'var(--color-accent-green)', dot: 'var(--color-accent-green)', blink: false }
    case 'disconnected':
      return { label: 'Reconnecting', color: 'var(--color-accent-yellow)', dot: 'var(--color-accent-yellow)', blink: true }
    case 'failed':
      return { label: 'Disconnected', color: 'var(--color-accent-red)', dot: 'var(--color-accent-red)', blink: false }
  }
}

function pillStyle(color: string): React.CSSProperties {
  return {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 6,
    padding: '4px 10px',
    background: 'var(--color-bg-tertiary)',
    borderRadius: 999,
    fontSize: 11,
    fontWeight: 600,
    color,
    letterSpacing: 0.5,
    textTransform: 'uppercase',
  }
}

function dotStyle(color: string, blink: boolean): React.CSSProperties {
  return {
    width: 7,
    height: 7,
    borderRadius: '50%',
    background: color,
    animation: blink ? 'pulse 1.2s ease-in-out infinite' : 'none',
  }
}
