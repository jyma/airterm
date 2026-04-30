import { useNavigate } from 'react-router-dom'
import { clearPairing, getStoredPairing } from '../lib/storage'

/// Minimal landing for paired devices. Phase 3's job is just to land
/// here after a successful pair — the takeover surface (terminal mirror,
/// command UI) lands in a later phase. For now we expose:
///   • the paired Mac's name + last-paired timestamp
///   • a "Forget" button so users can re-pair without devtools
export function PairedPage() {
  const navigate = useNavigate()
  const stored = getStoredPairing()

  if (!stored) {
    // Came here without a stored pairing (e.g. clearing storage in another
    // tab) — bounce back to /pair so the user re-establishes.
    navigate('/pair', { replace: true })
    return null
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
        <DetailRow label="Paired" value={formatDate(stored.pairedAt)} />
      </dl>

      <p style={hintStyle}>
        The takeover surface ships in a later phase. Once the Mac
        publishes its terminal stream, you'll see it here.
      </p>

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
