import { useCallback, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { QRScanner, type QRScannerError } from '../components/QRScanner'
import { PairClientError } from '../lib/pair-client'
import { runPhonePairFlow } from '../lib/pair-flow'
import { storePairing } from '../lib/storage'

type Mode = 'scan' | 'manual'
type Status =
  | { kind: 'idle' }
  | { kind: 'pairing' }
  | { kind: 'error'; message: string }

/// Entry point for unpaired users. Two paths:
///   1. **Scan QR** — camera + BarcodeDetector (preferred path on phones)
///   2. **Manual** — paste server URL + pair code + Mac public key. Fallback
///      for browsers without BarcodeDetector or for users who can't grant
///      camera permission. Same backend call, same persistence.
///
/// On success: persist the PairingInfo to localStorage and route to /paired.
export function PairPage() {
  const navigate = useNavigate()
  const [mode, setMode] = useState<Mode>('scan')
  const [scannerError, setScannerError] = useState<QRScannerError | null>(null)
  const [status, setStatus] = useState<Status>({ kind: 'idle' })

  const handleResult = useCallback(
    async (rawText: string) => {
      if (status.kind === 'pairing') return
      setStatus({ kind: 'pairing' })
      try {
        const info = await runPhonePairFlow(rawText)
        storePairing(info)
        navigate('/paired', { replace: true })
      } catch (e) {
        const message =
          e instanceof PairClientError
            ? e.message
            : e instanceof Error
              ? e.message
              : 'Pairing failed.'
        setStatus({ kind: 'error', message })
      }
    },
    [navigate, status.kind]
  )

  return (
    <main style={pageStyle}>
      <header style={headerStyle}>
        <h1 style={{ fontSize: 24, fontWeight: 600, margin: 0 }}>Pair with your Mac</h1>
        <p style={subtitleStyle}>
          Open AirTerm on your Mac, choose <em>Pair New Device</em>, and scan
          the QR code that appears.
        </p>
      </header>

      <section style={sectionStyle}>
        {mode === 'scan' ? (
          <>
            <QRScanner
              onResult={(text) => void handleResult(text)}
              onError={(err) => {
                setScannerError(err)
                setMode('manual')
              }}
            />
            <button
              type="button"
              style={secondaryButtonStyle}
              onClick={() => setMode('manual')}
            >
              Enter pair code manually
            </button>
            {scannerError && (
              <p style={{ color: 'var(--color-accent-yellow)', fontSize: 13, margin: 0 }}>
                {scannerError.message}
              </p>
            )}
          </>
        ) : (
          <ManualPairForm
            onSubmit={(rawJson) => void handleResult(rawJson)}
            onCancel={() => setMode('scan')}
          />
        )}
      </section>

      {status.kind === 'pairing' && <p style={infoStyle}>Pairing…</p>}
      {status.kind === 'error' && (
        <p style={errorStyle} role="alert">
          {status.message}
        </p>
      )}
    </main>
  )
}

interface ManualPairFormProps {
  readonly onSubmit: (rawJson: string) => void
  readonly onCancel: () => void
}

/// Manual fallback form. The user pastes the JSON the Mac shows under
/// the QR (or types each field). Submits as a full QR payload string so
/// the parser path is the same as the camera flow — no duplicated
/// validation between scan and manual.
function ManualPairForm({ onSubmit, onCancel }: ManualPairFormProps) {
  const [json, setJson] = useState('')
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault()
        onSubmit(json.trim())
      }}
      style={{ display: 'flex', flexDirection: 'column', gap: 12 }}
    >
      <label style={{ fontSize: 13, color: 'var(--color-text-secondary)' }}>
        Paste the JSON shown beneath the QR code:
      </label>
      <textarea
        value={json}
        onChange={(e) => setJson(e.target.value)}
        rows={6}
        style={textareaStyle}
        placeholder='{"v":2,"server":"https://relay.airterm.dev","pairCode":"…","macDeviceId":"…","macPublicKey":"…"}'
        autoCorrect="off"
        autoCapitalize="off"
        spellCheck={false}
      />
      <div style={{ display: 'flex', gap: 8 }}>
        <button type="submit" style={primaryButtonStyle} disabled={!json.trim()}>
          Pair
        </button>
        <button type="button" style={secondaryButtonStyle} onClick={onCancel}>
          Use camera instead
        </button>
      </div>
    </form>
  )
}

const pageStyle: React.CSSProperties = {
  maxWidth: 460,
  margin: '0 auto',
  padding: '24px 16px 48px',
  display: 'flex',
  flexDirection: 'column',
  gap: 24,
}

const headerStyle: React.CSSProperties = {
  display: 'flex',
  flexDirection: 'column',
  gap: 8,
}

const subtitleStyle: React.CSSProperties = {
  margin: 0,
  fontSize: 14,
  color: 'var(--color-text-secondary)',
  lineHeight: 1.5,
}

const sectionStyle: React.CSSProperties = {
  display: 'flex',
  flexDirection: 'column',
  gap: 12,
}

const primaryButtonStyle: React.CSSProperties = {
  flex: 1,
  padding: '12px 16px',
  border: 'none',
  borderRadius: 'var(--radius-button)',
  background: 'var(--color-accent-blue)',
  color: 'white',
  fontSize: 15,
  fontWeight: 600,
  cursor: 'pointer',
}

const secondaryButtonStyle: React.CSSProperties = {
  ...primaryButtonStyle,
  background: 'var(--color-bg-tertiary)',
  color: 'var(--color-text-primary)',
  fontWeight: 500,
}

const textareaStyle: React.CSSProperties = {
  background: 'var(--color-bg-input)',
  color: 'var(--color-text-primary)',
  border: '1px solid var(--color-border)',
  borderRadius: 'var(--radius-button)',
  padding: 12,
  fontFamily: 'var(--font-mono)',
  fontSize: 12,
  resize: 'vertical',
}

const infoStyle: React.CSSProperties = {
  margin: 0,
  fontSize: 14,
  color: 'var(--color-text-secondary)',
}

const errorStyle: React.CSSProperties = {
  margin: 0,
  padding: 12,
  background: 'var(--color-diff-del-bg)',
  color: 'var(--color-diff-del-text)',
  borderRadius: 'var(--radius-button)',
  fontSize: 14,
}
