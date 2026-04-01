import { useState, useCallback, useEffect } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { storePairing } from '@/lib/storage'
import type { PairCompleteResponse } from '@airterm/protocol'

const PAIR_CODE_RE = /^[A-Z0-9]{6}$/

function generateDeviceId(): string {
  const arr = new Uint8Array(16)
  crypto.getRandomValues(arr)
  return Array.from(arr, (b) => b.toString(16).padStart(2, '0')).join('')
}

export function PairPage() {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const [pairCode, setPairCode] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [status, setStatus] = useState<'input' | 'pairing' | 'done'>('input')

  // Auto-pair from QR code URL params
  const codeFromQR = searchParams.get('code')

  useEffect(() => {
    if (codeFromQR && PAIR_CODE_RE.test(codeFromQR.toUpperCase())) {
      setPairCode(codeFromQR.toUpperCase())
      doPair(codeFromQR.toUpperCase())
    }
  }, [codeFromQR])

  const doPair = useCallback(
    async (code: string) => {
      if (!PAIR_CODE_RE.test(code) || loading) return

      setLoading(true)
      setStatus('pairing')
      setError('')

      const phoneDeviceId = generateDeviceId()

      try {
        const res = await fetch('/api/pair/complete', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            pairCode: code,
            phoneDeviceId,
            phoneName: navigator.userAgent.includes('iPhone') ? 'iPhone' : 'Phone',
          }),
        })

        if (!res.ok) {
          const body = await res.json()
          setError(body.error ?? '配对失败')
          setStatus('input')
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

        setStatus('done')
        navigate('/sessions')
      } catch {
        setError('网络错误，请重试')
        setStatus('input')
      } finally {
        setLoading(false)
      }
    },
    [loading, navigate],
  )

  const handleSubmit = useCallback(
    (e: React.FormEvent) => {
      e.preventDefault()
      doPair(pairCode.trim().toUpperCase())
    },
    [pairCode, doPair],
  )

  // Auto-pairing from QR scan
  if (status === 'pairing' && codeFromQR) {
    return (
      <div className="flex flex-col items-center justify-center min-h-screen px-6 bg-bg-primary font-[family-name:var(--font-ui)]">
        <div className="w-16 h-16 rounded-2xl bg-accent-blue/10 flex items-center justify-center mb-6">
          <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="text-accent-blue animate-pulse">
            <path d="M12 22c5.523 0 10-4.477 10-10S17.523 2 12 2 2 6.477 2 12s4.477 10 10 10z" />
            <path d="M12 6v6l4 2" />
          </svg>
        </div>
        <p className="text-lg font-semibold text-text-primary">正在配对...</p>
        <p className="text-sm text-text-secondary mt-2">正在与 Mac 建立安全连接</p>
      </div>
    )
  }

  // Manual code entry
  return (
    <div className="flex flex-col items-center justify-center min-h-screen px-6 bg-bg-primary font-[family-name:var(--font-ui)]">
      <div className="w-full max-w-sm">
        {/* Logo */}
        <div className="flex flex-col items-center mb-10">
          <div className="w-16 h-16 rounded-2xl bg-accent-blue/10 flex items-center justify-center mb-4">
            <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="text-accent-blue">
              <rect x="2" y="3" width="20" height="14" rx="2" ry="2" />
              <line x1="8" y1="21" x2="16" y2="21" />
              <line x1="12" y1="17" x2="12" y2="21" />
            </svg>
          </div>
          <h1 className="text-2xl font-bold text-text-primary">AirTerm</h1>
          <p className="text-sm text-text-secondary mt-2 text-center">
            输入 Mac 上显示的配对码
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <input
            type="text"
            value={pairCode}
            onChange={(e) => setPairCode(e.target.value.replace(/[^A-Za-z0-9]/g, '').toUpperCase())}
            placeholder="ABC123"
            maxLength={6}
            autoFocus
            className="w-full px-4 py-4 bg-bg-secondary border border-border rounded-xl text-center text-2xl font-mono tracking-[0.3em] text-text-primary placeholder:text-text-muted focus:outline-none focus:border-accent-blue transition-colors"
          />

          {error && <p className="text-sm text-accent-red text-center">{error}</p>}

          <button
            type="submit"
            disabled={pairCode.length < 6 || loading}
            className="w-full py-3.5 bg-accent-blue text-white rounded-xl font-semibold text-sm disabled:opacity-40 active:scale-[0.98] transition-all"
          >
            {loading ? '配对中...' : '连接'}
          </button>
        </form>

        <div className="mt-8 text-center">
          <p className="text-xs text-text-muted leading-relaxed">
            在 Mac 菜单栏点击 AirTerm 图标
            <br />
            选择「配对新设备」获取配对码
          </p>
        </div>

        <div className="mt-6 flex items-center justify-center gap-2 text-xs text-text-muted">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
            <path d="M7 11V7a5 5 0 0 1 10 0v4" />
          </svg>
          <span>端到端加密 · 无需注册</span>
        </div>
      </div>
    </div>
  )
}
