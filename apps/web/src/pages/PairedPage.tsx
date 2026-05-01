import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { TakeoverViewer } from '../components/TakeoverViewer'
import { runPhoneReconnectFlow, PairingInfoMissingFieldsError } from '../lib/reconnect-flow'
import type { PairFlowResult } from '../lib/pair-flow'
import { clearPairing, getStoredPairing, storePairing } from '../lib/storage'

/// Landing page for already-paired browsers. Walks the user through
/// reconnect on mount: load stored pairing → re-run Noise IK against
/// the saved Mac static → mount TakeoverViewer if the handshake
/// succeeds. Failures (Mac offline, stale token) surface inline with
/// a "Re-pair" button instead of bouncing back to /pair, so the user
/// keeps their stored Mac context until they explicitly reset.
type Status =
  | { kind: 'idle' }
  | { kind: 'reconnecting' }
  | { kind: 'live'; pair: PairFlowResult }
  | { kind: 'error'; message: string }

export function PairedPage() {
  const navigate = useNavigate()
  const stored = getStoredPairing()
  const [status, setStatus] = useState<Status>({ kind: 'idle' })
  // Guard so React 18 strict-mode double-mount doesn't double-handshake.
  const startedRef = useRef(false)

  useEffect(() => {
    if (!stored) {
      navigate('/pair', { replace: true })
      return
    }
    if (startedRef.current) return
    startedRef.current = true
    setStatus({ kind: 'reconnecting' })

    runPhoneReconnectFlow(stored)
      .then((pair) => {
        storePairing(pair.pairingInfo)
        setStatus({ kind: 'live', pair })
      })
      .catch((err) => {
        const message =
          err instanceof PairingInfoMissingFieldsError
            ? 'This pairing was created by an older build that did not capture the Mac public key. Re-pair to upgrade.'
            : err instanceof Error
              ? err.message
              : 'Reconnect failed.'
        setStatus({ kind: 'error', message })
      })
    // No deps: stored only matters at mount; it doesn't change while we live.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  if (!stored) return null

  if (status.kind === 'live') {
    return (
      <main style={pageStyle}>
        <header style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <h1 style={{ fontSize: 18, fontWeight: 600, margin: 0 }}>
            Mirroring {stored.targetName}
          </h1>
          <p style={{ margin: 0, fontSize: 12, color: 'var(--color-text-muted)' }}>
            Reconnected · refresh to re-handshake
          </p>
        </header>
        <TakeoverViewer channel={status.pair.channel} />
        <button
          type="button"
          style={dangerButtonStyle}
          onClick={() => {
            try { status.pair.ws.disconnect() } catch { /* may be closed */ }
            clearPairing()
            navigate('/pair', { replace: true })
          }}
        >
          Forget this Mac
        </button>
      </main>
    )
  }

  return (
    <main style={pageStyle}>
      <header style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <h1 style={{ fontSize: 24, fontWeight: 600, margin: 0 }}>Paired</h1>
        <p style={{ margin: 0, fontSize: 14, color: 'var(--color-text-secondary)' }}>
          Connected to <strong>{stored.targetName}</strong>
        </p>
      </header>

      <dl style={dlStyle}>
        <DetailRow label="Server" value={stored.serverUrl} />
        <DetailRow label="Mac device id" value={short(stored.targetDeviceId)} mono />
        <DetailRow label="Last paired" value={formatDate(stored.pairedAt)} />
      </dl>

      {status.kind === 'reconnecting' && (
        <p style={hintStyle}>Reconnecting securely to {stored.targetName}…</p>
      )}
      {status.kind === 'error' && (
        <div style={errorBoxStyle} role="alert">
          <p style={{ margin: 0, fontWeight: 500 }}>Couldn't reconnect</p>
          <p style={{ margin: '4px 0 0', fontSize: 13 }}>{status.message}</p>
        </div>
      )}

      <button
        type="button"
        style={dangerButtonStyle}
        onClick={() => {
          clearPairing()
          navigate('/pair', { replace: true })
        }}
      >
        Forget this Mac
      </button>
    </main>
  )
}

interface DetailRowProps {
  readonly label: string
  readonly value: string
  readonly mono?: boolean
}

function DetailRow({ label, value, mono }: DetailRowProps) {
  return (
    <div style={rowStyle}>
      <dt style={{ color: 'var(--color-text-secondary)', fontSize: 13 }}>{label}</dt>
      <dd
        style={{
          margin: 0,
          fontSize: 14,
          color: 'var(--color-text-primary)',
          fontFamily: mono ? 'var(--font-mono)' : 'inherit',
          wordBreak: 'break-all',
        }}
      >
        {value}
      </dd>
    </div>
  )
}

function short(id: string): string {
  return id.length > 16 ? `${id.slice(0, 8)}…${id.slice(-4)}` : id
}

function formatDate(ts: number): string {
  return new Date(ts).toLocaleString()
}

const pageStyle: React.CSSProperties = {
  maxWidth: 460,
  margin: '0 auto',
  padding: '24px 16px 48px',
  display: 'flex',
  flexDirection: 'column',
  gap: 24,
}

const dlStyle: React.CSSProperties = {
  display: 'flex',
  flexDirection: 'column',
  gap: 4,
  margin: 0,
  padding: 16,
  background: 'var(--color-bg-secondary)',
  borderRadius: 'var(--radius-card)',
}

const rowStyle: React.CSSProperties = {
  display: 'flex',
  flexDirection: 'column',
  gap: 2,
  paddingBlock: 8,
  borderBottom: '1px solid var(--color-border)',
}

const hintStyle: React.CSSProperties = {
  margin: 0,
  fontSize: 13,
  color: 'var(--color-text-muted)',
  lineHeight: 1.5,
}

const errorBoxStyle: React.CSSProperties = {
  padding: 12,
  background: 'var(--color-diff-del-bg)',
  color: 'var(--color-diff-del-text)',
  borderRadius: 'var(--radius-button)',
  fontSize: 14,
}

const dangerButtonStyle: React.CSSProperties = {
  padding: '12px 16px',
  border: '1px solid var(--color-accent-red)',
  borderRadius: 'var(--radius-button)',
  background: 'transparent',
  color: 'var(--color-accent-red)',
  fontSize: 14,
  fontWeight: 500,
  cursor: 'pointer',
}
