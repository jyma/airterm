import type {
  TerminalEvent,
  DiffEvent,
  DiffHunk as DiffHunkType,
  ToolCallEvent,
  MessageEvent,
  ApprovalEvent,
  CompletionEvent,
} from '@airterm/protocol'

interface TerminalPaneProps {
  readonly events: readonly TerminalEvent[]
  readonly sessionId?: string
  readonly onApprove?: (sessionId: string) => void
  readonly onDeny?: (sessionId: string) => void
}

function ClaudeMessage({ event }: { readonly event: MessageEvent }) {
  return (
    <div className="animate-[message-in_0.2s_ease-out] space-y-0.5">
      <div className="text-accent-blue font-mono text-xs">╭─ Claude</div>
      {event.text.split('\n').map((line, i) => (
        <div key={i} className="text-text-primary font-mono text-xs">
          <span className="text-accent-blue">│</span>{' '}
          <span>{line}</span>
        </div>
      ))}
      <div className="text-text-muted font-mono text-xs">╰─</div>
    </div>
  )
}

function DiffBlock({ event }: { readonly event: DiffEvent }) {
  return (
    <div className="animate-[message-in_0.2s_ease-out]">
      <div className="text-accent-purple font-mono text-xs">► Edit {event.file}</div>
      <div className="mt-1 bg-bg-secondary rounded-md py-1 px-3 space-y-0.5">
        {event.hunks.map((hunk, hi) => (
          <DiffHunkView key={hi} hunk={hunk} />
        ))}
      </div>
    </div>
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

        const colorClass =
          line.op === 'add'
            ? 'text-diff-add-text'
            : line.op === 'remove'
              ? 'text-diff-del-text'
              : 'text-text-secondary'
        const prefix = line.op === 'add' ? '+' : line.op === 'remove' ? '-' : ' '

        return (
          <div key={li} className={`font-mono text-[11px] ${colorClass}`}>
            <span className="inline-block w-6 text-right mr-2 text-text-muted select-none">
              {displayNum}
            </span>
            <span className="mr-1">│</span>
            <span className="select-none">{prefix} </span>
            {line.text}
          </div>
        )
      })}
    </>
  )
}

function ToolCallItem({ event }: { readonly event: ToolCallEvent }) {
  const color =
    event.tool === 'Bash' ? 'text-accent-cyan' :
    event.tool === 'Read' ? 'text-accent-cyan' :
    'text-accent-purple'

  return (
    <div className="animate-[message-in_0.2s_ease-out]">
      <div className={`font-mono text-xs ${color}`}>
        ► {event.tool}
        {'file' in event.args && event.args.file != null && ` ${String(event.args.file)}`}
        {event.tool === 'Bash' && 'command' in event.args && event.args.command != null && ` ${String(event.args.command)}`}
      </div>
      {event.output && <ToolOutput output={event.output} />}
    </div>
  )
}

function ToolOutput({ output }: { readonly output: string }) {
  return (
    <div className="font-mono text-xs whitespace-pre-wrap mt-0.5 ml-3">
      {output.split('\n').map((line, i) => {
        const trimmed = line.trim()
        const lineColor =
          trimmed.startsWith('PASS') ? 'text-accent-green' :
          trimmed.startsWith('FAIL') ? 'text-accent-red' :
          trimmed.startsWith('✓') || trimmed.includes('passed') ? 'text-accent-green' :
          trimmed.startsWith('✗') || trimmed.includes('failed') ? 'text-accent-red' :
          'text-text-secondary'
        return <div key={i} className={lineColor}>{line}</div>
      })}
    </div>
  )
}

interface ApprovalBlockProps {
  readonly event: ApprovalEvent
  readonly sessionId?: string
  readonly onApprove?: (sessionId: string) => void
  readonly onDeny?: (sessionId: string) => void
}

function ApprovalBlock({ event, sessionId, onApprove, onDeny }: ApprovalBlockProps) {
  return (
    <div className="animate-[message-in_0.2s_ease-out] bg-bg-secondary rounded-lg p-3 space-y-2.5">
      <div className="font-mono text-xs text-accent-yellow">⚠ Claude wants to run:</div>
      <div className="bg-bg-tertiary rounded-md px-2.5 py-1.5">
        <span className="font-mono text-xs text-text-primary">{event.command}</span>
      </div>
      {sessionId && onApprove && onDeny && (
        <div className="flex gap-2.5">
          <button
            onClick={() => onDeny(sessionId)}
            className="flex-1 h-10 rounded-lg bg-bg-tertiary font-[family-name:var(--font-ui)] text-sm font-semibold text-accent-red active:opacity-70 transition-opacity"
          >
            Deny
          </button>
          <button
            onClick={() => onApprove(sessionId)}
            className="flex-1 h-10 rounded-lg bg-accent-blue font-[family-name:var(--font-ui)] text-sm font-semibold text-white active:opacity-70 transition-opacity"
          >
            Allow
          </button>
        </div>
      )}
    </div>
  )
}

function CompletionItem({ event }: { readonly event: CompletionEvent }) {
  return (
    <div className="animate-[message-in_0.2s_ease-out] font-mono text-xs text-accent-green">
      ✓ {event.summary}
    </div>
  )
}

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

export function TerminalPane({ events, sessionId, onApprove, onDeny }: TerminalPaneProps) {
  return (
    <div className="flex-1 overflow-y-auto bg-bg-primary px-3.5 py-3 space-y-1.5">
      {events.length === 0 ? (
        <div className="flex items-center justify-center h-full text-text-muted text-xs font-mono">
          Waiting for output...
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
