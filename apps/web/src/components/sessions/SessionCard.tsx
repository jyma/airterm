import type { SessionInfo } from '@airterm/protocol'

interface SessionCardProps {
  readonly session: SessionInfo
  readonly selected?: boolean
  readonly compact?: boolean
  readonly onClick: () => void
}

const STATUS_STYLES: Record<string, { dot: string; label: string }> = {
  active: { dot: 'bg-accent-green animate-[pulse_2s_ease-in-out_infinite]', label: '运行中' },
  connected: { dot: 'bg-accent-blue', label: '已连接' },
  discovered: { dot: 'bg-accent-yellow', label: '已发现' },
  ended: { dot: 'bg-text-muted', label: '已结束' },
}

export function SessionCard({ session, selected = false, compact = false, onClick }: SessionCardProps) {
  const status = STATUS_STYLES[session.status] ?? STATUS_STYLES.ended
  const needsApproval = session.needsApproval

  return (
    <button
      onClick={onClick}
      className={`w-full text-left bg-bg-secondary rounded-[var(--radius-card)] transition-all active:scale-[0.98] border ${
        needsApproval
          ? 'border-accent-yellow'
          : selected
            ? 'border-accent-blue'
            : 'border-transparent hover:border-border'
      } ${compact ? 'p-3' : 'p-4'}`}
    >
      <div className="flex items-center gap-2">
        <span className={`w-2 h-2 rounded-full shrink-0 ${status.dot}`} />
        <span className={`font-semibold text-text-primary truncate ${compact ? 'text-sm' : 'text-base'}`}>
          {session.name}
        </span>
        {needsApproval && (
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="ml-auto text-accent-yellow shrink-0">
            <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
            <line x1="12" y1="9" x2="12" y2="13" /><line x1="12" y1="17" x2="12.01" y2="17" />
          </svg>
        )}
        {!needsApproval && (
          <span className="ml-auto text-xs text-text-muted shrink-0">{status.label}</span>
        )}
      </div>

      <div className="mt-1 text-xs text-text-muted font-[family-name:var(--font-mono)] truncate">
        {session.cwd}
      </div>

      {session.lastOutput && (
        <div className={`mt-1.5 text-text-secondary truncate ${compact ? 'text-xs' : 'text-sm'}`}>
          {session.lastOutput}
        </div>
      )}

      {!compact && session.terminal && (
        <div className="mt-1.5 text-xs text-text-muted">
          {session.terminal}
        </div>
      )}
    </button>
  )
}
