import { useNavigate } from 'react-router-dom'
import { getStoredTheme, setTheme } from '@/lib/theme'
import { getStoredPairing, clearPairing } from '@/lib/storage'
import { useState } from 'react'

type Theme = 'dark' | 'light' | 'system'

export function SettingsPage() {
  const navigate = useNavigate()
  const pairing = getStoredPairing()
  const [currentTheme, setCurrentTheme] = useState<Theme>(getStoredTheme())

  const handleThemeChange = (theme: Theme) => {
    setCurrentTheme(theme)
    setTheme(theme)
  }

  const handleUnpair = () => {
    clearPairing()
    navigate('/pair')
  }

  return (
    <div className="min-h-screen bg-bg-primary">
      {/* Header */}
      <div className="flex items-center gap-3 px-4 py-3 bg-bg-secondary border-b border-border">
        <button onClick={() => navigate(-1)} className="text-accent-blue text-sm">
          ← Back
        </button>
        <span className="text-sm font-medium text-text-primary">Settings</span>
      </div>

      <div className="p-4 space-y-6">
        {/* Theme */}
        <section>
          <h3 className="text-xs text-text-muted uppercase tracking-wider mb-2">Appearance</h3>
          <div className="bg-bg-secondary rounded-xl border border-border divide-y divide-border">
            {(['system', 'light', 'dark'] as const).map((t) => (
              <button
                key={t}
                onClick={() => handleThemeChange(t)}
                className="w-full flex items-center justify-between px-4 py-3 text-sm text-text-primary"
              >
                <span className="capitalize">{t}</span>
                {currentTheme === t && <span className="text-accent-blue">✓</span>}
              </button>
            ))}
          </div>
        </section>

        {/* Paired device */}
        {pairing && (
          <section>
            <h3 className="text-xs text-text-muted uppercase tracking-wider mb-2">Paired Device</h3>
            <div className="bg-bg-secondary rounded-xl border border-border p-4">
              <div className="text-sm text-text-primary">{pairing.targetName}</div>
              <div className="text-xs text-text-muted mt-1">
                {pairing.targetDeviceId.slice(0, 8)}...
              </div>
              <button
                onClick={handleUnpair}
                className="mt-3 text-sm text-accent-red hover:underline"
              >
                Unpair Device
              </button>
            </div>
          </section>
        )}

        {/* About */}
        <section>
          <h3 className="text-xs text-text-muted uppercase tracking-wider mb-2">About</h3>
          <div className="bg-bg-secondary rounded-xl border border-border p-4">
            <div className="text-sm text-text-primary">AirTerm v0.1.0</div>
            <div className="text-xs text-text-muted mt-1">Remote control for Claude Code CLI</div>
          </div>
        </section>
      </div>
    </div>
  )
}
