import type { SessionInfo } from '@airterm/protocol'

interface PaneHeaderProps {
  readonly session: SessionInfo
  readonly onExpand?: () => void
}

const STATUS_COLORS: Record<string, string> = {
  active: 'bg-accent-green',
  connected: 'bg-accent-blue',
  discovered: 'bg-accent-yellow',
  ended: 'bg-text-muted',
}

export function PaneHeader({ session, onExpand }: PaneHeaderProps) {
  return (
    <div
      className="flex items-center gap-2 px-3 py-1.5 bg-bg-tertiary border-b border-border cursor-pointer select-none"
      onClick={onExpand}
    >
      <span
        className={`w-1.5 h-1.5 rounded-full ${STATUS_COLORS[session.status] ?? 'bg-text-muted'}`}
      />
      <span className="text-xs font-medium text-text-primary truncate">{session.name}</span>
      <span className="text-xs text-text-muted truncate ml-auto">{session.cwd}</span>
      {session.needsApproval && (
        <span className="w-2 h-2 rounded-full bg-accent-yellow animate-pulse" />
      )}
    </div>
  )
}
