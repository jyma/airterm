import type { SessionInfo, TerminalEvent } from '@airterm/protocol'
import { TerminalPane } from '@/components/terminal/TerminalPane'

interface MultiPaneViewProps {
  readonly sessions: readonly SessionInfo[]
  readonly events: Record<string, readonly TerminalEvent[]>
  readonly onApprove: (sessionId: string) => void
  readonly onDeny: (sessionId: string) => void
}

const STATUS_COLORS: Record<string, string> = {
  active: 'bg-accent-green',
  connected: 'bg-accent-blue',
  discovered: 'bg-accent-yellow',
  ended: 'bg-text-muted',
}

const STATUS_LABELS: Record<string, string> = {
  active: '运行中',
  connected: '已连接',
  discovered: '已发现',
  ended: '已结束',
}

function PaneTitle({ session }: { readonly session: SessionInfo }) {
  const needsApproval = session.needsApproval

  return (
    <div className="flex items-center gap-2 px-3 h-[32px] bg-bg-secondary shrink-0 border-b border-border">
      <span className={`w-1.5 h-1.5 rounded-full ${STATUS_COLORS[session.status] ?? 'bg-text-muted'} ${
        session.status === 'active' ? 'animate-[pulse_2s_ease-in-out_infinite]' : ''
      }`} />
      <span className="text-xs font-semibold text-text-primary font-[family-name:var(--font-ui)] truncate">
        {session.name}
      </span>
      <span className="text-[10px] text-text-muted font-mono truncate">
        {session.cwd}
      </span>
      <span className={`ml-auto text-[10px] font-medium font-[family-name:var(--font-ui)] px-1.5 py-0.5 rounded shrink-0 ${
        needsApproval
          ? 'bg-accent-yellow/20 text-accent-yellow'
          : 'bg-bg-tertiary text-text-secondary'
      }`}>
        {needsApproval ? '等待确认' : STATUS_LABELS[session.status] ?? session.status}
      </span>
    </div>
  )
}

export function MultiPaneView({ sessions, events, onApprove, onDeny }: MultiPaneViewProps) {
  // Distribute height: first pane gets more space
  const getFlexBasis = (index: number, total: number): string => {
    if (total === 1) return '100%'
    if (total === 2) return index === 0 ? '60%' : '40%'
    // 3+ panes
    if (index === 0) return '45%'
    if (index === 1) return '30%'
    return '25%'
  }

  return (
    <div className="flex-1 flex flex-col overflow-hidden divide-y divide-border">
      {sessions.map((session, i) => (
        <div
          key={session.id}
          className="flex flex-col min-h-0 overflow-hidden"
          style={{ flex: `0 0 ${getFlexBasis(i, sessions.length)}` }}
        >
          <PaneTitle session={session} />
          <TerminalPane
            events={events[session.id] ?? []}
            sessionId={session.id}
            onApprove={onApprove}
            onDeny={onDeny}
          />
        </div>
      ))}
    </div>
  )
}
