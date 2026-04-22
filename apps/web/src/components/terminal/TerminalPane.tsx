import { useState, useRef, useEffect, useCallback, useMemo } from 'react'
import { renderMarkdown } from '@/lib/markdown'
import type {
  TerminalEvent,
  DiffEvent,
  DiffHunk as DiffHunkType,
  ToolCallEvent,
  MessageEvent,
  ApprovalEvent,
  CompletionEvent,
} from '@airterm/protocol'

// ─── Utilities ───────────────────────────────────────────────

function formatTime(ts?: number): string {
  if (!ts) {
    const now = new Date()
    return `${now.getHours()}:${String(now.getMinutes()).padStart(2, '0')}`
  }
  const d = new Date(ts)
  return `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`
}

function haptic(style: 'light' | 'medium' = 'light'): void {
  if ('vibrate' in navigator) {
    navigator.vibrate(style === 'light' ? 10 : 20)
  }
}

// ─── Props ───────────────────────────────────────────────────

interface TerminalPaneProps {
  readonly events: readonly TerminalEvent[]
  readonly sessionId?: string
  readonly onApprove?: (sessionId: string) => void
  readonly onDeny?: (sessionId: string) => void
}

// ─── Claude Message ──────────────────────────────────────────

function ClaudeMessage({ event }: { readonly event: MessageEvent }) {
  const html = useMemo(() => renderMarkdown(event.text), [event.text])

  return (
    <div className="animate-[message-in_0.2s_ease-out] select-text">
      <div className="bg-bg-secondary rounded-[var(--radius-card)] p-3 px-4">
        <div className="text-xs text-accent-blue font-[family-name:var(--font-ui)] mb-1.5">
          — Claude
        </div>
        <div
          className="text-sm text-text-primary font-[family-name:var(--font-ui)] leading-relaxed"
          dangerouslySetInnerHTML={{ __html: html }}
        />
        <div className="text-[10px] text-text-muted mt-2 text-right font-[family-name:var(--font-ui)]">
          {formatTime()}
        </div>
      </div>
    </div>
  )
}

// ─── Tool Card (collapsible) ─────────────────────────────────

function ToolCard({
  tool,
  label,
  children,
  defaultOpen = false,
}: {
  readonly tool: string
  readonly label: string
  readonly children: React.ReactNode
  readonly defaultOpen?: boolean
}) {
  const [open, setOpen] = useState(defaultOpen)

  const borderColor =
    tool === 'Bash' ? 'border-l-accent-cyan' :
    tool === 'Edit' ? 'border-l-accent-yellow' :
    tool === 'Read' ? 'border-l-accent-blue' :
    tool === 'Write' ? 'border-l-accent-green' :
    tool === 'Grep' ? 'border-l-accent-purple' :
    'border-l-accent-blue'

  const iconColor =
    tool === 'Bash' ? 'text-accent-cyan' :
    tool === 'Edit' ? 'text-accent-yellow' :
    tool === 'Read' ? 'text-accent-blue' :
    tool === 'Write' ? 'text-accent-green' :
    tool === 'Grep' ? 'text-accent-purple' :
    'text-accent-blue'

  return (
    <div className={`animate-[message-in_0.2s_ease-out] bg-bg-secondary rounded-lg border-l-[3px] ${borderColor} overflow-hidden`}>
      <button
        onClick={() => setOpen(!open)}
        className="w-full flex items-center justify-between px-3 py-2 hover:bg-bg-tertiary/30 transition-colors"
        aria-expanded={open}
      >
        <span className={`font-[family-name:var(--font-mono)] text-xs ${iconColor}`}>
          ▶ {label}
        </span>
        <svg
          width="14"
          height="14"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          className={`text-text-muted transition-transform duration-[var(--duration-fast)] ${open ? '' : '-rotate-90'}`}
        >
          <polyline points="6 9 12 15 18 9" />
        </svg>
      </button>
      {open && (
        <div className="px-3 pb-2.5 font-[family-name:var(--font-mono)] text-xs select-text">
          {children}
        </div>
      )}
    </div>
  )
}

// ─── Diff Block ──────────────────────────────────────────────

function DiffBlock({ event }: { readonly event: DiffEvent }) {
  return (
    <ToolCard tool="Edit" label={`Edit ${event.file}`} defaultOpen>
      {/* File header */}
      <div className="text-[10px] text-text-secondary bg-bg-tertiary/50 px-2 py-1 rounded-t mb-px">
        {event.file}
      </div>
      <div className="space-y-px rounded-b overflow-hidden">
        {event.hunks.map((hunk, hi) => (
          <DiffHunkView key={hi} hunk={hunk} />
        ))}
      </div>
    </ToolCard>
  )
}

function DiffHunkView({ hunk }: { readonly hunk: DiffHunkType }) {
  let oldLine = hunk.oldStart
  let newLine = hunk.oldStart

  return (
    <>
      {hunk.lines.map((line, li) => {
        const displayNum = line.op === 'add' ? newLine : oldLine
        if (line.op !== 'add') oldLine++
        if (line.op !== 'remove') newLine++

        const bgClass =
          line.op === 'add' ? 'bg-diff-add-bg' :
          line.op === 'remove' ? 'bg-diff-del-bg' :
          ''

        const textClass =
          line.op === 'add' ? 'text-diff-add-text' :
          line.op === 'remove' ? 'text-diff-del-text' :
          'text-text-secondary'

        const prefix = line.op === 'add' ? '+' : line.op === 'remove' ? '-' : ' '

        return (
          <div key={li} className={`flex ${bgClass}`}>
            <span className="inline-block w-8 text-right pr-2 text-text-muted select-none shrink-0 text-[11px] leading-5">
              {displayNum}
            </span>
            <span className={`${textClass} text-[11px] leading-5`}>
              <span className="select-none">{prefix} </span>
              {line.text}
            </span>
          </div>
        )
      })}
    </>
  )
}

// ─── Tool Call ────────────────────────────────────────────────

function ToolCallItem({ event }: { readonly event: ToolCallEvent }) {
  const fileArg = 'file' in event.args && event.args.file != null ? String(event.args.file) : undefined
  const cmdArg = 'command' in event.args && event.args.command != null ? String(event.args.command) : undefined

  const label =
    event.tool === 'Bash' && cmdArg ? `Bash ${cmdArg}` :
    (event.tool === 'Read' || event.tool === 'Edit' || event.tool === 'Write') && fileArg
      ? `${event.tool} ${fileArg}` :
    event.tool

  const hasOutput = Boolean(event.output)

  return (
    <ToolCard tool={event.tool} label={label} defaultOpen={hasOutput}>
      {event.output && <ToolOutput output={event.output} />}
    </ToolCard>
  )
}

function ToolOutput({ output }: { readonly output: string }) {
  const lines = output.split('\n')
  const isLong = lines.length > 30
  const [expanded, setExpanded] = useState(!isLong)

  const displayLines = expanded ? lines : lines.slice(0, 10)

  return (
    <div className="whitespace-pre-wrap text-[11px] leading-relaxed bg-bg-tertiary/50 rounded p-2 mt-1">
      {displayLines.map((line, i) => {
        const trimmed = line.trim()
        const lineColor =
          trimmed.startsWith('PASS') || trimmed.includes('passed') || trimmed.startsWith('✓')
            ? 'text-accent-green'
            : trimmed.startsWith('FAIL') || trimmed.includes('failed') || trimmed.startsWith('✗')
              ? 'text-accent-red'
              : 'text-text-secondary'
        return <div key={i} className={lineColor}>{line}</div>
      })}
      {isLong && !expanded && (
        <button
          onClick={() => setExpanded(true)}
          className="text-accent-blue text-[11px] mt-1 hover:underline"
        >
          展开全部 ({lines.length} 行)
        </button>
      )}
    </div>
  )
}

// ─── Approval Block ──────────────────────────────────────────

interface ApprovalBlockProps {
  readonly event: ApprovalEvent
  readonly sessionId?: string
  readonly onApprove?: (sessionId: string) => void
  readonly onDeny?: (sessionId: string) => void
}

function ApprovalBlock({ event, sessionId, onApprove, onDeny }: ApprovalBlockProps) {
  return (
    <div className="animate-[approval-in_0.3s_ease-out] bg-bg-secondary border border-accent-yellow shadow-[0_0_0_1px_var(--color-accent-yellow),0_0_12px_rgba(255,214,10,0.15)] rounded-[var(--radius-card)] p-4 space-y-3">
      <div className="flex items-center gap-2 text-sm font-semibold text-accent-yellow font-[family-name:var(--font-ui)]">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
          <line x1="12" y1="9" x2="12" y2="13" /><line x1="12" y1="17" x2="12.01" y2="17" />
        </svg>
        需要确认
      </div>
      <div className="text-xs text-text-secondary font-[family-name:var(--font-ui)]">
        允许执行 {event.tool}:
      </div>
      <div className="bg-bg-tertiary rounded-md px-3 py-2">
        <span className="font-[family-name:var(--font-mono)] text-sm text-text-primary">{event.command}</span>
      </div>
      {sessionId && onApprove && onDeny && (
        <div className="flex gap-3">
          <button
            onClick={() => { haptic(); onDeny(sessionId) }}
            className="flex-1 h-12 rounded-[var(--radius-button)] border border-border font-[family-name:var(--font-ui)] text-sm font-semibold text-text-primary active:scale-[0.96] active:opacity-80 transition-all"
          >
            拒绝
          </button>
          <button
            onClick={() => { haptic('medium'); onApprove(sessionId) }}
            className="flex-1 h-12 rounded-[var(--radius-button)] bg-accent-green font-[family-name:var(--font-ui)] text-sm font-semibold text-white active:scale-[0.96] active:opacity-80 transition-all"
          >
            允许
          </button>
        </div>
      )}
    </div>
  )
}

// ─── Completion ──────────────────────────────────────────────

function CompletionItem({ event }: { readonly event: CompletionEvent }) {
  return (
    <div className="animate-[message-in_0.2s_ease-out] font-[family-name:var(--font-mono)] text-xs text-accent-green py-1">
      ✓ {event.summary}
    </div>
  )
}

// ─── Event Router ────────────────────────────────────────────

interface EventItemProps {
  readonly event: TerminalEvent
  readonly sessionId?: string
  readonly onApprove?: (sessionId: string) => void
  readonly onDeny?: (sessionId: string) => void
}

function EventItem({ event, sessionId, onApprove, onDeny }: EventItemProps) {
  switch (event.type) {
    case 'message':
      return <ClaudeMessage event={event} />
    case 'diff':
      return <DiffBlock event={event} />
    case 'tool_call':
      return <ToolCallItem event={event} />
    case 'approval':
      return <ApprovalBlock event={event} sessionId={sessionId} onApprove={onApprove} onDeny={onDeny} />
    case 'completion':
      return <CompletionItem event={event} />
  }
}

// ─── Main Component ──────────────────────────────────────────

export function TerminalPane({ events, sessionId, onApprove, onDeny }: TerminalPaneProps) {
  const scrollRef = useRef<HTMLDivElement>(null)
  const isUserScrollingRef = useRef(false)
  const prevEventsLenRef = useRef(0)

  // Detect user scroll — stop auto-scroll when user scrolls up
  const handleScroll = useCallback(() => {
    const el = scrollRef.current
    if (!el) return
    const distFromBottom = el.scrollHeight - el.scrollTop - el.clientHeight
    isUserScrollingRef.current = distFromBottom > 50
  }, [])

  // Auto-scroll to bottom on new events (unless user scrolled up)
  useEffect(() => {
    if (events.length > prevEventsLenRef.current && !isUserScrollingRef.current) {
      scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' })
    }
    prevEventsLenRef.current = events.length
  }, [events])

  return (
    <div
      ref={scrollRef}
      onScroll={handleScroll}
      className="flex-1 overflow-y-auto bg-bg-primary px-4 py-3 space-y-3"
    >
      {events.length === 0 ? (
        <div className="flex flex-col items-center justify-center h-full text-text-muted text-xs font-[family-name:var(--font-mono)] gap-2">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="opacity-50">
            <rect x="2" y="3" width="20" height="14" rx="2" ry="2" />
            <line x1="8" y1="21" x2="16" y2="21" />
            <line x1="12" y1="17" x2="12" y2="21" />
          </svg>
          等待输出...
        </div>
      ) : (
        events.map((event, i) => (
          <EventItem
            key={`${event.type}-${i}`}
            event={event}
            sessionId={sessionId}
            onApprove={onApprove}
            onDeny={onDeny}
          />
        ))
      )}
    </div>
  )
}
