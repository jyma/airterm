import type { SessionInfo } from '@airterm/protocol'

interface PaneHeaderProps {
  readonly session: SessionInfo
  readonly onBack?: () => void
}

const STATUS_LABELS: Record<string, string> = {
  active: '运行中',
  connected: '已连接',
  discovered: '已发现',
  ended: '已结束',
}

export function PaneHeader({ session, onBack }: PaneHeaderProps) {
  return (
    <div className="flex items-center justify-between px-4 h-[50px] bg-bg-secondary shrink-0">
      <div className="flex items-center gap-2">
        {onBack && (
          <button
            onClick={onBack}
            className="text-accent-blue shrink-0"
            aria-label="Back"
          >
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="15 18 9 12 15 6" />
            </svg>
          </button>
        )}
        <span className="text-base font-semibold text-text-primary truncate font-[family-name:var(--font-ui)]">
          {session.name}
        </span>
      </div>
      <div className="flex items-center gap-2.5 shrink-0">
        <span className={`w-1.5 h-1.5 rounded-full ${
          session.status === 'active' ? 'bg-accent-green animate-[pulse_2s_ease-in-out_infinite]' :
          session.status === 'ended' ? 'bg-text-muted' : 'bg-accent-blue'
        }`} />
        <span className="text-[10px] text-text-secondary font-medium font-[family-name:var(--font-ui)] bg-bg-tertiary px-2 py-0.5 rounded">
          {STATUS_LABELS[session.status] ?? session.status}
        </span>
      </div>
    </div>
  )
}
