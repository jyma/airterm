import { useState, useCallback, useRef, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { TopBar } from '@/components/ui/TopBar'
import { PaneHeader } from '@/components/terminal/PaneHeader'
import { TerminalPane } from '@/components/terminal/TerminalPane'
import { ApprovalBar } from '@/components/approval/ApprovalBar'
import { QuickPanel } from '@/components/shortcuts/QuickPanel'
import { useWebSocket } from '@/hooks/useWebSocket'
import { useSessions } from '@/hooks/useSessions'
import { getStoredPairing } from '@/lib/storage'
import type { ApprovalEvent } from '@airterm/protocol'

export function SessionsPage() {
  const navigate = useNavigate()
  const pairing = getStoredPairing()
  const [inputText, setInputText] = useState('')
  const [activeSessionId, setActiveSessionId] = useState<string | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)

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
      setInputText('')
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

  const handleSubmit = useCallback(
    (e: React.FormEvent) => {
      e.preventDefault()
      handleSendInput(inputText)
    },
    [inputText, handleSendInput],
  )

  // Find approval pending for active session
  const activeEvents = activeSessionId ? (events[activeSessionId] ?? []) : []
  const pendingApproval = [...activeEvents]
    .reverse()
    .find((e): e is ApprovalEvent => e.type === 'approval')
  const activeSession = sessions.find((s) => s.id === activeSessionId)

  if (!pairing) return null

  return (
    <div className="flex flex-col h-screen bg-bg-primary">
      <TopBar
        connectionState={connectionState}
        sessionCount={sessions.length}
        onSettingsClick={() => navigate('/settings')}
      />

      {/* Session tabs */}
      {sessions.length > 1 && (
        <div className="flex overflow-x-auto no-scrollbar border-b border-border">
          {sessions.map((s) => (
            <button
              key={s.id}
              onClick={() => setActiveSessionId(s.id)}
              className={`shrink-0 px-4 py-2 text-xs border-b-2 transition-colors ${
                s.id === activeSessionId
                  ? 'border-accent-blue text-text-primary'
                  : 'border-transparent text-text-secondary hover:text-text-primary'
              }`}
            >
              {s.name}
              {s.needsApproval && <span className="ml-1 text-accent-yellow">●</span>}
            </button>
          ))}
        </div>
      )}

      {/* Terminal content */}
      {activeSession ? (
        <>
          <PaneHeader session={activeSession} />
          <TerminalPane events={activeEvents} />
        </>
      ) : (
        <div className="flex-1 flex items-center justify-center text-text-muted text-sm">
          {connectionState === 'connected'
            ? 'No active sessions. Start claude on your Mac.'
            : 'Connecting to Mac...'}
        </div>
      )}

      {/* Approval bar */}
      {activeSession?.needsApproval && pendingApproval && (
        <ApprovalBar
          sessionId={activeSession.id}
          prompt={pendingApproval.prompt}
          onApprove={handleApprove}
          onDeny={handleDeny}
        />
      )}

      {/* Quick panel + input */}
      <div className="border-t border-border bg-bg-secondary">
        <QuickPanel onSend={handleShortcut} />
        <form onSubmit={handleSubmit} className="flex gap-2 px-4 pb-4 pt-1">
          <input
            ref={inputRef}
            type="text"
            value={inputText}
            onChange={(e) => setInputText(e.target.value)}
            placeholder="Send a message..."
            className="flex-1 px-3 py-2.5 bg-bg-tertiary border border-border rounded-lg text-sm text-text-primary placeholder:text-text-muted focus:outline-none focus:border-accent-blue transition-colors"
          />
          <button
            type="submit"
            disabled={!inputText.trim() || !activeSessionId}
            className="px-4 py-2.5 bg-accent-blue text-white rounded-lg text-sm font-medium disabled:opacity-40 hover:brightness-110 active:scale-95 transition-all"
          >
            Send
          </button>
        </form>
      </div>
    </div>
  )
}
