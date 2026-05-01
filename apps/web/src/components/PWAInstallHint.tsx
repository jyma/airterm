import { useEffect, useState } from 'react'

/// Friendly nudge shown only on iOS Safari, when the user hasn't yet
/// added AirTerm to their home screen. Taps "Got it" to dismiss for
/// good (persisted in localStorage).
///
/// We intentionally don't try to detect Android Chrome's
/// beforeinstallprompt or trigger a programmatic install on desktop
/// browsers — those have native UI built in. iOS, by contrast, has
/// no install UI at all and most users will never find the
/// Share → "Add to Home Screen" path on their own.
const DISMISSED_KEY = 'airterm.pwaHintDismissed'

interface PWAInstallHintProps {
  readonly inline?: boolean
}

export function PWAInstallHint({ inline = false }: PWAInstallHintProps) {
  const [show, setShow] = useState(false)

  useEffect(() => {
    if (!shouldShowHint()) return
    setShow(true)
  }, [])

  if (!show) return null

  return (
    <aside style={inline ? inlineStyle : floatingStyle} role="note">
      <p style={textStyle}>
        Tap <strong>Share</strong> → <strong>Add to Home Screen</strong> to
        launch AirTerm full-screen, like a native app.
      </p>
      <button
        type="button"
        style={dismissStyle}
        onClick={() => {
          localStorage.setItem(DISMISSED_KEY, '1')
          setShow(false)
        }}
        aria-label="Dismiss install hint"
      >
        Got it
      </button>
    </aside>
  )
}

function shouldShowHint(): boolean {
  // Only iOS Safari — not Chrome / Firefox on iOS (they alias as
  // CriOS / FxiOS) which don't expose the home-screen install path.
  const ua = navigator.userAgent
  const isIOS = /iPhone|iPad|iPod/.test(ua) && !/CriOS|FxiOS|EdgiOS/.test(ua)
  if (!isIOS) return false

  // Don't show when the user already opened AirTerm from the home
  // screen as a standalone PWA.
  const standaloneNav = (navigator as { standalone?: boolean }).standalone === true
  const standaloneMQ = window.matchMedia('(display-mode: standalone)').matches
  if (standaloneNav || standaloneMQ) return false

  // One-shot per device.
  return localStorage.getItem(DISMISSED_KEY) !== '1'
}

const sharedStyle: React.CSSProperties = {
  background: 'var(--color-bg-secondary)',
  border: '1px solid var(--color-border)',
  borderRadius: 'var(--radius-card)',
  padding: 12,
  display: 'flex',
  alignItems: 'center',
  gap: 12,
  fontSize: 13,
  color: 'var(--color-text-primary)',
  lineHeight: 1.4,
}

const inlineStyle: React.CSSProperties = {
  ...sharedStyle,
}

const floatingStyle: React.CSSProperties = {
  ...sharedStyle,
  position: 'sticky',
  top: 8,
  zIndex: 5,
  boxShadow: 'var(--shadow-card)',
}

const textStyle: React.CSSProperties = {
  margin: 0,
  flex: 1,
}

const dismissStyle: React.CSSProperties = {
  flex: '0 0 auto',
  padding: '6px 12px',
  background: 'var(--color-bg-tertiary)',
  color: 'var(--color-text-primary)',
  border: 0,
  borderRadius: 8,
  fontSize: 13,
  fontWeight: 500,
  cursor: 'pointer',
}
