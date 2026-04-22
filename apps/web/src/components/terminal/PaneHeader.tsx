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

const STATUS_COLORS: Record<string, { dot: string; pill: string }> = {
  active: {
    dot: 'bg-accent-green animate-[pulse_2s_ease-in-out_infinite]',
    pill: 'bg-accent-green/15 text-accent-green',
  },
  connected: {
    dot: 'bg-accent-blue',
    pill: 'bg-accent-blue/15 text-accent-blue',
  },
  discovered: {
    dot: 'bg-accent-yellow',
    pill: 'bg-accent-yellow/15 text-accent-yellow',
  },
  ended: {
    dot: 'bg-text-muted',
    pill: 'bg-bg-tertiary text-text-muted',
  },
}

export function PaneHeader({ session, onBack }: PaneHeaderProps) {
  const status = STATUS_COLORS[session.status] ?? STATUS_COLORS.ended
  const label = STATUS_LABELS[session.status] ?? session.status

  return (
    <div className="flex items-center justify-between px-4 h-[50px] bg-bg-secondary shrink-0 border-b border-border">
      <div className="flex items-center gap-2 min-w-0">
        {onBack && (
          <button
            onClick={onBack}
            className="text-accent-blue shrink-0 -ml-1"
            aria-label="Back"
          >
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="15 18 9 12 15 6" />
            </svg>
          </button>
        )}
        <span className="text-base font-semibold text-text-primary truncate">
          {session.name}
        </span>
      </div>
      <div className="flex items-center gap-1.5 shrink-0 ml-3">
        <span className={`w-1.5 h-1.5 rounded-full ${status.dot}`} />
        <span className={`text-[11px] font-medium px-2 py-0.5 rounded-full ${status.pill}`}>
          {label}
        </span>
      </div>
    </div>
  )
}
