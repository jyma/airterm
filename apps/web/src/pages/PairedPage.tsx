import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ConnectionPill } from '../components/ConnectionPill'
import { TakeoverViewer } from '../components/TakeoverViewer'
import { ConnectionManager, type ConnState } from '../lib/connection-manager'
import { PairingInfoMissingFieldsError } from '../lib/reconnect-flow'
import { clearPairing, getStoredPairing } from '../lib/storage'
import type { TakeoverChannel } from '../lib/takeover-channel'

/// Landing page for already-paired browsers. Owns a long-lived
/// `ConnectionManager` so a Mac restart, a network blip, or a
/// background-tab freeze all recover automatically — the user sees
/// the connection pill flip "Live → Reconnecting → Live" without
/// having to navigate, refresh, or re-pair.
export function PairedPage() {
  const navigate = useNavigate()
  const stored = getStoredPairing()
  const [state, setState] = useState<ConnState>('connecting')
  const [channel, setChannel] = useState<TakeoverChannel | null>(null)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const managerRef = useRef<ConnectionManager | null>(null)
  const startedRef = useRef(false)

  useEffect(() => {
    if (!stored) {
      navigate('/pair', { replace: true })
      return
    }
    if (startedRef.current) return
    startedRef.current = true

    const manager = new ConnectionManager({
      stored,
      onStateChange: (s) => {
        setState(s)
        if (s === 'live' || s === 'connecting' || s === 'handshaking') {
          setErrorMessage(null)
        }
      },
      onChannelChange: (c) => setChannel(c),
      onError: (err) => {
        const message =
          err instanceof PairingInfoMissingFieldsError
            ? 'This pairing was created by an older build that did not capture the Mac public key. Re-pair to upgrade.'
            : err.message || 'Connection failed.'
        setErrorMessage(message)
      },
    })
    managerRef.current = manager
    void manager.start()

    return () => {
      manager.stop()
      managerRef.current = null
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  if (!stored) return null

  return (
    <main style={pageStyle}>
      <header style={headerRow}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <h1 style={{ fontSize: 18, fontWeight: 600, margin: 0 }}>
            {stored.targetName}
          </h1>
          <p style={{ margin: 0, fontSize: 12, color: 'var(--color-text-muted)' }}>
            {stored.serverUrl}
          </p>
        </div>
        <ConnectionPill state={state} />
      </header>

      {channel && state === 'live' ? (
        <TakeoverViewer channel={channel} />
      ) : (
        <PlaceholderPanel state={state} message={errorMessage} />
      )}

      <button
        type="button"
        style={dangerButtonStyle}
        onClick={() => {
          managerRef.current?.stop()
          clearPairing()
          navigate('/pair', { replace: true })
        }}
      >
        Forget this Mac
      </button>
    </main>
  )
}

interface PlaceholderProps {
  readonly state: ConnState
  readonly message: string | null
}

/// Renders while we're not in the `live` state. Splits the messaging
/// between transient (we'll recover) vs terminal (manual action
/// required) so users know whether to wait or re-pair.
function PlaceholderPanel({ state, message }: PlaceholderProps) {
  const transient =
    state === 'connecting' ||
    state === 'handshaking' ||
    state === 'disconnected'
  return (
    <div style={placeholderStyle}>
      {transient && (
        <p style={transientText}>
          {state === 'connecting' && 'Reaching the relay…'}
          {state === 'handshaking' && 'Securing channel…'}
          {state === 'disconnected' && 'Lost connection — retrying.'}
        </p>
      )}
      {state === 'failed' && (
        <div style={errorBoxStyle} role="alert">
          <p style={{ margin: 0, fontWeight: 500 }}>Couldn't reconnect</p>
          <p style={{ margin: '4px 0 0', fontSize: 13 }}>
            {message ?? 'Try refreshing or re-pairing.'}
          </p>
        </div>
      )}
    </div>
  )
}

const pageStyle: React.CSSProperties = {
  maxWidth: 460,
  margin: '0 auto',
  padding: '16px 16px 24px',
  display: 'flex',
  flexDirection: 'column',
  gap: 12,
}

const headerRow: React.CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  gap: 12,
}

const placeholderStyle: React.CSSProperties = {
  display: 'flex',
  flexDirection: 'column',
  gap: 12,
  minHeight: 240,
  padding: 16,
  borderRadius: 'var(--radius-card)',
  background: 'var(--color-bg-overlay)',
  alignItems: 'center',
  justifyContent: 'center',
}

const transientText: React.CSSProperties = {
  margin: 0,
  fontSize: 14,
  color: 'var(--color-text-secondary)',
}

const errorBoxStyle: React.CSSProperties = {
  width: '100%',
  padding: 12,
  background: 'var(--color-diff-del-bg)',
  color: 'var(--color-diff-del-text)',
  borderRadius: 'var(--radius-button)',
  fontSize: 14,
}

const dangerButtonStyle: React.CSSProperties = {
  padding: '10px 14px',
  border: '1px solid var(--color-accent-red)',
  borderRadius: 'var(--radius-button)',
  background: 'transparent',
  color: 'var(--color-accent-red)',
  fontSize: 13,
  fontWeight: 500,
  cursor: 'pointer',
  alignSelf: 'flex-start',
}
