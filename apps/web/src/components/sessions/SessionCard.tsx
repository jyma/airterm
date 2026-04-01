import type { SessionInfo } from '@airterm/protocol'

interface SessionCardProps {
  readonly session: SessionInfo
  readonly selected?: boolean
  readonly onClick: () => void
}

const STATUS_STYLES: Record<string, { dot: string; label: string }> = {
  active: { dot: 'bg-accent-green animate-[pulse_2s_ease-in-out_infinite]', label: '运行中' },
  connected: { dot: 'bg-accent-blue', label: '已连接' },
  discovered: { dot: 'bg-accent-yellow', label: '已发现' },
  ended: { dot: 'bg-text-muted', label: '已结束' },
}

export function SessionCard({ session, selected = false, onClick }: SessionCardProps) {
  const status = STATUS_STYLES[session.status] ?? STATUS_STYLES.ended
  const needsApproval = session.needsApproval

  return (
    <button
      onClick={onClick}
      className={`w-full text-left bg-bg-secondary rounded-xl p-4 transition-all active:scale-[0.98] border ${
        needsApproval
          ? 'border-accent-yellow'
          : selected
            ? 'border-accent-blue'
            : 'border-transparent hover:border-border'
      }`}
    >
      <div className="flex items-center gap-2">
        <span className={`w-2 h-2 rounded-full shrink-0 ${status.dot}`} />
        <span className="text-base font-semibold text-text-primary truncate font-[family-name:var(--font-ui)]">
          {session.name}
        </span>
        {needsApproval && <span className="ml-auto text-accent-yellow shrink-0">⚠️</span>}
        {!needsApproval && (
          <span className="ml-auto text-xs text-text-muted shrink-0">{status.label}</span>
        )}
      </div>
      <div className="mt-1 text-xs text-text-muted font-mono truncate">{session.cwd}</div>
      {session.lastOutput && (
        <div className="mt-2 text-sm text-text-secondary truncate">{session.lastOutput}</div>
      )}
      <div className="mt-2 text-xs text-text-muted font-[family-name:var(--font-ui)]">
        {session.terminal}
      </div>
    </button>
  )
}
