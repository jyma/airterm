import { useState, useCallback, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { TopBar } from '@/components/ui/TopBar'
import { MultiPaneView } from '@/components/sessions/MultiPaneView'
import { SessionCard } from '@/components/sessions/SessionCard'
import { PaneHeader } from '@/components/terminal/PaneHeader'
import { TerminalPane } from '@/components/terminal/TerminalPane'
import { QuickPanel } from '@/components/shortcuts/QuickPanel'
import { InputBar } from '@/components/input/InputBar'
import { useWebSocket } from '@/hooks/useWebSocket'
import { useSessions } from '@/hooks/useSessions'
import { getStoredPairing } from '@/lib/storage'

function useIsDesktop() {
  const [isDesktop, setIsDesktop] = useState(() => {
    if (typeof window === 'undefined') return false
    return window.matchMedia('(min-width: 769px)').matches
  })
  useEffect(() => {
    const mq = window.matchMedia('(min-width: 769px)')
    setIsDesktop(mq.matches)
    const handler = (e: MediaQueryListEvent) => setIsDesktop(e.matches)
    mq.addEventListener('change', handler)
    return () => mq.removeEventListener('change', handler)
  }, [])
  return isDesktop
}

export function SessionsPage() {
  const navigate = useNavigate()
  const pairing = getStoredPairing()
  const isDesktop = useIsDesktop()
  const [activeSessionId, setActiveSessionId] = useState<string | null>(null)

  const { sessions, events, handleMessage } = useSessions()

  const wsUrl = pairing ? `${pairing.serverUrl.replace(/^http/, 'ws')}/ws/phone` : ''

  const { state: connectionState, send } = useWebSocket({
    url: wsUrl,
    token: pairing?.token ?? '',
    deviceId: pairing?.deviceId ?? '',
    targetDeviceId: pairing?.targetDeviceId ?? '',
    onMessage: handleMessage,
  })

  useEffect(() => {
    if (!pairing) {
      navigate('/pair')
    }
  }, [pairing, navigate])

  // Auto-select first session
  useEffect(() => {
    if (!activeSessionId && sessions.length > 0) {
      setActiveSessionId(sessions[0].id)
    }
  }, [activeSessionId, sessions])

  const handleSendInput = useCallback(
    (text: string) => {
      if (!activeSessionId || !text.trim()) return
      send({ kind: 'input', sessionId: activeSessionId, text })
    },
    [activeSessionId, send],
  )

  const handleApprove = useCallback(
    (sessionId: string) => {
      send({ kind: 'approval', sessionId, action: 'allow' })
    },
    [send],
  )

  const handleDeny = useCallback(
    (sessionId: string) => {
      send({ kind: 'approval', sessionId, action: 'deny' })
    },
    [send],
  )

  const handleShortcut = useCallback(
    (command: string) => {
      if (!activeSessionId) return
      send({ kind: 'shortcut', sessionId: activeSessionId, command })
    },
    [activeSessionId, send],
  )

  const activeEvents = activeSessionId ? (events[activeSessionId] ?? []) : []
  const activeSession = sessions.find((s) => s.id === activeSessionId)

  if (!pairing) return null

  // Desktop: sidebar + detail
  if (isDesktop) {
    return (
      <div className="flex flex-col h-screen bg-bg-primary">
        <TopBar
          connectionState={connectionState}
          onSettingsClick={() => navigate('/settings')}
        />
        <div className="flex flex-1 overflow-hidden">
          {/* Sidebar */}
          <aside className="w-[280px] shrink-0 border-r border-border overflow-y-auto bg-bg-primary p-3 space-y-2">
            {sessions.map((s) => (
              <SessionCard
                key={s.id}
                session={s}
                selected={s.id === activeSessionId}
                onClick={() => setActiveSessionId(s.id)}
              />
            ))}
            {sessions.length === 0 && (
              <div className="flex items-center justify-center h-32 text-text-muted text-sm font-[family-name:var(--font-ui)]">
                暂无会话
              </div>
            )}
          </aside>

          {/* Detail panel */}
          <main className="flex-1 flex flex-col overflow-hidden">
            {activeSession ? (
              <>
                <PaneHeader session={activeSession} />
                <TerminalPane
                  events={activeEvents}
                  sessionId={activeSession.id}
                  onApprove={handleApprove}
                  onDeny={handleDeny}
                />
                <div className="bg-bg-secondary px-3.5 py-2 space-y-2">
                  <InputBar onSend={handleSendInput} disabled={!activeSessionId} />
                  <QuickPanel onSend={handleShortcut} />
                </div>
              </>
            ) : (
              <div className="flex-1 flex items-center justify-center text-text-muted text-sm font-[family-name:var(--font-ui)]">
                {connectionState === 'connected'
                  ? '选择一个会话查看详情'
                  : '正在连接 Mac...'}
              </div>
            )}
          </main>
        </div>
      </div>
    )
  }

  // Mobile: multi-pane tmux view (when sessions exist)
  if (sessions.length > 0) {
    return (
      <div className="flex flex-col h-screen bg-bg-primary">
        <TopBar
          connectionState={connectionState}
          onSettingsClick={() => navigate('/settings')}
        />
        <MultiPaneView
          sessions={sessions}
          events={events}
          onApprove={handleApprove}
          onDeny={handleDeny}
        />
        <div className="bg-bg-secondary px-3.5 py-2 pb-[max(0.5rem,env(safe-area-inset-bottom))] space-y-2">
          <InputBar onSend={handleSendInput} disabled={!activeSessionId} />
          <QuickPanel onSend={handleShortcut} />
        </div>
      </div>
    )
  }

  // Mobile: empty state
  return (
    <div className="flex flex-col h-screen bg-bg-primary">
      <TopBar
        connectionState={connectionState}
        onSettingsClick={() => navigate('/settings')}
      />
      <div className="flex-1 flex flex-col items-center justify-center text-text-muted text-sm font-[family-name:var(--font-ui)]">
        {connectionState === 'connected' ? (
          <>
            <span className="text-3xl mb-3">📡</span>
            <span>暂无活跃会话</span>
            <span className="text-xs mt-1">在 Mac 上启动 Claude Code 开始使用</span>
          </>
        ) : (
          <>
            <span className="text-3xl mb-3">🔄</span>
            <span>正在连接 Mac...</span>
          </>
        )}
      </div>
    </div>
  )
}
