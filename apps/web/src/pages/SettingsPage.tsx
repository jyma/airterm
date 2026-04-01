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
    <div className="min-h-screen bg-bg-primary font-[family-name:var(--font-ui)]">
      {/* Header */}
      <header className="sticky top-0 z-50 flex items-center gap-3 px-4 py-3 bg-bg-secondary/80 backdrop-blur-xl border-b border-border">
        <button
          onClick={() => navigate(-1)}
          className="text-accent-blue text-sm font-medium"
          aria-label="Back"
        >
          ‹ 返回
        </button>
        <span className="text-sm font-semibold text-text-primary">设置</span>
      </header>

      <div className="p-4 space-y-6 pb-12">
        {/* Appearance */}
        <Section title="外观">
          <Card>
            <Row label="主题">
              <select
                value={currentTheme}
                onChange={(e) => handleThemeChange(e.target.value as Theme)}
                className="bg-transparent text-sm text-text-secondary text-right appearance-none cursor-pointer focus:outline-none"
              >
                {(['system', 'light', 'dark'] as const).map((t) => (
                  <option key={t} value={t}>
                    {THEME_LABELS[t]}
                  </option>
                ))}
              </select>
            </Row>
          </Card>
        </Section>

        {/* Connection */}
        <Section title="连接">
          <Card>
            <Row label="状态">
              <div className="flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-accent-green" />
                <span className="text-sm text-accent-green">已连接</span>
              </div>
            </Row>
          </Card>
        </Section>

        {/* Paired devices */}
        {pairing && (
          <Section title="已配对设备">
            <Card>
              <div className="px-4 py-3">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="text-sm font-medium text-text-primary">
                      {pairing.targetName}
                    </div>
                    <div className="text-xs text-text-muted mt-0.5">
                      配对于 {new Date().toLocaleDateString('zh-CN', { month: 'long', day: 'numeric' })}
                    </div>
                  </div>
                  <button
                    onClick={handleUnpair}
                    className="text-sm text-accent-red font-medium"
                  >
                    撤销
                  </button>
                </div>
              </div>
            </Card>
            <button
              onClick={() => navigate('/pair')}
              className="w-full mt-3 py-3 rounded-xl border border-accent-blue text-sm text-accent-blue font-medium active:scale-[0.98] transition-transform"
            >
              + 配对新设备
            </button>
          </Section>
        )}

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
              <span className="text-sm text-text-secondary">30 分钟</span>
            </Row>
          </Card>
        </Section>

        {/* About */}
        <Section title="关于">
          <Card>
            <div className="px-4 py-3">
              <div className="text-sm text-text-primary">AirTerm v0.1.0</div>
              <div className="text-xs text-text-muted mt-1">Remote control for Claude Code CLI</div>
            </div>
          </Card>
        </Section>
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
      <h3 className="text-xs text-text-muted uppercase tracking-wider mb-2 px-1">{title}</h3>
      {children}
    </section>
  )
}

function Card({ children }: { readonly children: React.ReactNode }) {
  return (
    <div className="bg-bg-secondary rounded-xl border border-border overflow-hidden">
      {children}
    </div>
  )
}

function Row({ label, children }: { readonly label: string; readonly children: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between px-4 py-3">
      <span className="text-sm text-text-primary">{label}</span>
      {children}
    </div>
  )
}

function Divider() {
  return <div className="border-t border-border mx-4" />
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
      className={`relative w-11 h-6 rounded-full transition-colors ${
        checked ? 'bg-accent-green' : 'bg-bg-tertiary'
      }`}
    >
      <span
        className={`absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-white shadow transition-transform ${
          checked ? 'translate-x-5' : 'translate-x-0'
        }`}
      />
    </button>
  )
}

