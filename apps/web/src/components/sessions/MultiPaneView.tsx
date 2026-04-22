import { useState, useEffect } from 'react'
import type { SessionInfo, TerminalEvent } from '@airterm/protocol'
import { TerminalPane } from '@/components/terminal/TerminalPane'
import { PaneHeader } from '@/components/terminal/PaneHeader'

interface MultiPaneViewProps {
  readonly sessions: readonly SessionInfo[]
  readonly events: Record<string, readonly TerminalEvent[]>
  readonly activeSessionId: string | null
  readonly onSelectSession: (sessionId: string) => void
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

function PaneTitle({
  session,
  isActive,
}: {
  readonly session: SessionInfo
  readonly isActive: boolean
}) {
  const needsApproval = session.needsApproval

  return (
    <div className={`flex items-center gap-2 px-3 h-[34px] shrink-0 border-b border-border ${
      isActive ? 'bg-accent-blue/10' : 'bg-bg-secondary'
    }`}>
      <span className={`w-1.5 h-1.5 rounded-full ${STATUS_COLORS[session.status] ?? 'bg-text-muted'} ${
        session.status === 'active' ? 'animate-[pulse_2s_ease-in-out_infinite]' : ''
      }`} />
      <span className="text-xs font-semibold text-text-primary truncate">
        {session.name}
      </span>
      <span className="text-[10px] text-text-muted font-[family-name:var(--font-mono)] truncate">
        {session.cwd}
      </span>
      <span className={`ml-auto text-[10px] font-medium px-1.5 py-0.5 rounded shrink-0 ${
        needsApproval
          ? 'bg-accent-yellow/20 text-accent-yellow'
          : 'bg-bg-tertiary text-text-secondary'
      }`}>
        {needsApproval ? '等待确认' : STATUS_LABELS[session.status] ?? session.status}
      </span>
    </div>
  )
}

export function MultiPaneView({
  sessions,
  events,
  activeSessionId,
  onSelectSession,
  onApprove,
  onDeny,
}: MultiPaneViewProps) {
  const [expandedId, setExpandedId] = useState<string | null>(null)

  // Sync active session when expanding
  const handleExpand = (sessionId: string) => {
    setExpandedId(sessionId)
    onSelectSession(sessionId)
  }

  const handleCollapse = () => {
    setExpandedId(null)
    // Keep the activeSessionId as the first session for input bar
    if (sessions.length > 0) {
      onSelectSession(sessions[0].id)
    }
  }

  // Auto-select first session when none selected
  useEffect(() => {
    if (!activeSessionId && sessions.length > 0) {
      onSelectSession(sessions[0].id)
    }
  }, [activeSessionId, sessions, onSelectSession])

  // Expanded single session view
  if (expandedId) {
    const session = sessions.find(s => s.id === expandedId)
    if (session) {
      return (
        <div className="flex-1 flex flex-col overflow-hidden animate-[slide-in-right_0.2s_ease-out]">
          <PaneHeader
            session={session}
            onBack={handleCollapse}
          />
          <TerminalPane
            events={events[session.id] ?? []}
            sessionId={session.id}
            onApprove={onApprove}
            onDeny={onDeny}
          />
        </div>
      )
    }
  }

  // Tmux-style multi-pane split
  const getFlexBasis = (index: number, total: number): string => {
    if (total === 1) return '100%'
    if (total === 2) return index === 0 ? '55%' : '45%'
    if (index === 0) return '40%'
    if (index === 1) return '35%'
    return '25%'
  }

  return (
    <div className="flex-1 flex flex-col overflow-hidden divide-y divide-border">
      {sessions.map((session, i) => {
        const isActive = session.id === activeSessionId
        return (
          <div
            key={session.id}
            className="flex flex-col min-h-0 overflow-hidden"
            style={{ flex: `0 0 ${getFlexBasis(i, sessions.length)}` }}
          >
            <button
              onClick={() => handleExpand(session.id)}
              className="w-full text-left"
              aria-label={`展开 ${session.name} 会话`}
            >
              <PaneTitle session={session} isActive={isActive} />
            </button>
            <div onFocus={() => onSelectSession(session.id)} tabIndex={-1}>
              <TerminalPane
                events={events[session.id] ?? []}
                sessionId={session.id}
                onApprove={onApprove}
                onDeny={onDeny}
              />
            </div>
          </div>
        )
      })}
    </div>
  )
}
