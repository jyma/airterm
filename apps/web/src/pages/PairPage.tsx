import { useState, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { storePairing } from '@/lib/storage'
import type { PairCompleteResponse } from '@airterm/protocol'

function generateDeviceId(): string {
  const arr = new Uint8Array(16)
  crypto.getRandomValues(arr)
  return Array.from(arr, (b) => b.toString(16).padStart(2, '0')).join('')
}

export function PairPage() {
  const navigate = useNavigate()
  const [pairCode, setPairCode] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  const handleSubmit = useCallback(
    async (e: React.FormEvent) => {
      e.preventDefault()
      if (!pairCode.trim() || loading) return

      setLoading(true)
      setError('')

      const phoneDeviceId = generateDeviceId()

      try {
        const res = await fetch('/api/pair/complete', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            pairCode: pairCode.trim().toUpperCase(),
            phoneDeviceId,
            phoneName: navigator.userAgent.includes('iPhone') ? 'iPhone' : 'Phone',
          }),
        })

        if (!res.ok) {
          const body = await res.json()
          setError(body.error ?? 'Pairing failed')
          return
        }

        const data = (await res.json()) as PairCompleteResponse

        storePairing({
          token: data.token,
          deviceId: phoneDeviceId,
          targetDeviceId: data.macDeviceId,
          targetName: data.macName,
          serverUrl: window.location.origin,
        })

        navigate('/sessions')
      } catch {
        setError('Network error, please try again')
      } finally {
        setLoading(false)
      }
    },
    [pairCode, loading, navigate],
  )

  return (
    <div className="flex flex-col items-center justify-center min-h-screen px-6 bg-bg-primary">
      <div className="w-full max-w-sm">
        <h1 className="text-2xl font-bold text-text-primary text-center mb-2">AirTerm</h1>
        <p className="text-sm text-text-secondary text-center mb-8">
          Enter the pair code shown on your Mac
        </p>

        <form onSubmit={handleSubmit} className="space-y-4">
          <input
            type="text"
            value={pairCode}
            onChange={(e) => setPairCode(e.target.value.toUpperCase())}
            placeholder="ABC123"
            maxLength={6}
            autoFocus
            className="w-full px-4 py-3 bg-bg-tertiary border border-border rounded-xl text-center text-2xl font-mono tracking-[0.3em] text-text-primary placeholder:text-text-muted focus:outline-none focus:border-accent-blue transition-colors"
          />

          {error && <p className="text-sm text-accent-red text-center">{error}</p>}

          <button
            type="submit"
            disabled={pairCode.length < 6 || loading}
            className="w-full py-3 bg-accent-blue text-white rounded-xl font-medium text-sm disabled:opacity-40 hover:brightness-110 active:scale-[0.98] transition-all"
          >
            {loading ? 'Pairing...' : 'Connect'}
          </button>
        </form>
      </div>
    </div>
  )
}
