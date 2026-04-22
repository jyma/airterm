import { useNavigate } from 'react-router-dom'
import { getStoredTheme, setTheme } from '@/lib/theme'
import { getStoredPairing, clearPairing } from '@/lib/storage'
import { useState } from 'react'

type Theme = 'dark' | 'light' | 'system'

const THEME_LABELS: Record<Theme, string> = {
  system: '跟随系统',
  light: '亮色',
  dark: '暗色',
}

export function SettingsPage() {
  const navigate = useNavigate()
  const pairing = getStoredPairing()
  const [currentTheme, setCurrentTheme] = useState<Theme>(getStoredTheme())
  const [dangerBlock, setDangerBlock] = useState(() => localStorage.getItem('airterm-danger-block') !== 'false')
  const [opLog, setOpLog] = useState(() => localStorage.getItem('airterm-op-log') !== 'false')

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
      {/* Header with glass effect */}
      <header className="sticky top-0 z-50 flex items-center gap-3 px-4 h-[50px] glass border-b border-border">
        <button
          onClick={() => navigate(-1)}
          className="flex items-center gap-1 text-accent-blue text-sm font-medium"
          aria-label="Back"
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="15 18 9 12 15 6" />
          </svg>
          设置
        </button>
      </header>

      <div className="p-4 space-y-6 pb-12">
        {/* Appearance */}
        <Section title="外观">
          <Card>
            <Row label="主题">
              <div className="flex items-center gap-1">
                <select
                  value={currentTheme}
                  onChange={(e) => handleThemeChange(e.target.value as Theme)}
                  className="bg-transparent text-sm text-text-secondary text-right appearance-none cursor-pointer focus:outline-none pr-4"
                >
                  {(['system', 'light', 'dark'] as const).map((t) => (
                    <option key={t} value={t}>
                      {THEME_LABELS[t]}
                    </option>
                  ))}
                </select>
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="text-text-muted">
                  <polyline points="6 9 12 15 18 9" />
                </svg>
              </div>
            </Row>
          </Card>
        </Section>

        {/* Connection */}
        <Section title="连接">
          <Card>
            <Row label="状态">
              <div className="flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-accent-green" />
                <span className="text-sm text-accent-green font-medium">已连接</span>
              </div>
            </Row>
          </Card>
        </Section>

        {/* Paired devices */}
        <Section title="已配对设备">
          {pairing && (
            <Card>
              <div className="px-4 py-3">
                <div className="flex items-start justify-between">
                  <div>
                    <div className="text-sm font-medium text-text-primary">
                      {pairing.targetName}
                    </div>
                    <div className="text-xs text-text-muted mt-0.5">
                      配对于 {new Date(pairing.pairedAt).toLocaleDateString('zh-CN', { month: 'long', day: 'numeric' })} · 最后活跃: 刚刚
                    </div>
                  </div>
                  <button
                    onClick={handleUnpair}
                    className="text-sm text-accent-red font-medium shrink-0"
                  >
                    撤销
                  </button>
                </div>
              </div>
            </Card>
          )}
          <button
            onClick={() => navigate('/pair')}
            className="w-full mt-3 py-3 rounded-[var(--radius-card)] border border-accent-blue text-sm text-accent-blue font-medium active:scale-[0.98] transition-transform"
          >
            + 配对新设备
          </button>
        </Section>

        {/* Security */}
        <Section title="安全">
          <Card>
            <Row label="高危命令确认">
              <Toggle checked={dangerBlock} onChange={(v) => { setDangerBlock(v); localStorage.setItem('airterm-danger-block', String(v)) }} />
            </Row>
            <Divider />
            <Row label="操作日志">
              <Toggle checked={opLog} onChange={(v) => { setOpLog(v); localStorage.setItem('airterm-op-log', String(v)) }} />
            </Row>
            <Divider />
            <Row label="自动锁定">
              <div className="flex items-center gap-1">
                <span className="text-sm text-text-secondary">30 分钟</span>
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="text-text-muted">
                  <polyline points="6 9 12 15 18 9" />
                </svg>
              </div>
            </Row>
          </Card>
        </Section>

        {/* About */}
        <div className="text-center pt-4">
          <div className="text-xs text-text-muted">AirTerm v0.1.0</div>
        </div>
      </div>
    </div>
  )
}

function Section({
  title,
  children,
}: {
  readonly title: string
  readonly children: React.ReactNode
}) {
  return (
    <section>
      <h3 className="text-xs text-text-muted uppercase tracking-wider mb-2 px-1 font-medium">{title}</h3>
      {children}
    </section>
  )
}

function Card({ children }: { readonly children: React.ReactNode }) {
  return (
    <div className="bg-bg-secondary rounded-[var(--radius-card)] overflow-hidden">
      {children}
    </div>
  )
}

function Row({ label, children }: { readonly label: string; readonly children: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between px-4 h-[50px]">
      <span className="text-sm text-text-primary">{label}</span>
      {children}
    </div>
  )
}

function Divider() {
  return <div className="border-t border-border ml-4" />
}

function Toggle({
  checked,
  onChange,
}: {
  readonly checked: boolean
  readonly onChange: (v: boolean) => void
}) {
  return (
    <button
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className={`relative w-[51px] h-[31px] rounded-full transition-colors ${
        checked ? 'bg-accent-green' : 'bg-bg-tertiary'
      }`}
    >
      <span
        className={`absolute top-[2px] left-[2px] w-[27px] h-[27px] rounded-full bg-white shadow-sm transition-transform ${
          checked ? 'translate-x-[20px]' : 'translate-x-0'
        }`}
      />
    </button>
  )
}
