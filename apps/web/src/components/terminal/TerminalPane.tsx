import type { TerminalEvent, DiffEvent } from '@airterm/protocol'

interface TerminalPaneProps {
  readonly events: readonly TerminalEvent[]
}

function DiffBlock({ event }: { readonly event: DiffEvent }) {
  return (
    <div className="my-1 rounded-md overflow-hidden border border-border">
      <div className="px-3 py-1 bg-bg-tertiary text-xs text-text-secondary">{event.file}</div>
      <div className="font-mono text-xs leading-5">
        {event.hunks.map((hunk, hi) => (
          <div key={hi}>
            {hunk.lines.map((line, li) => {
              const bgClass =
                line.op === 'add'
                  ? 'bg-diff-add-bg text-diff-add-text'
                  : line.op === 'remove'
                    ? 'bg-diff-del-bg text-diff-del-text'
                    : 'text-text-secondary'
              const prefix = line.op === 'add' ? '+' : line.op === 'remove' ? '-' : ' '
              return (
                <div key={li} className={`px-3 ${bgClass}`}>
                  <span className="select-none mr-2 text-text-muted">{prefix}</span>
                  {line.text}
                </div>
              )
            })}
          </div>
        ))}
      </div>
    </div>
  )
}

function EventItem({ event }: { readonly event: TerminalEvent }) {
  switch (event.type) {
    case 'message':
      return (
        <div className="px-3 py-2 text-sm text-text-primary whitespace-pre-wrap">{event.text}</div>
      )
    case 'diff':
      return <DiffBlock event={event} />
    case 'tool_call':
      return (
        <div className="mx-3 my-1 px-3 py-2 rounded-md bg-bg-tertiary border border-border">
          <div className="flex items-center gap-2 text-xs">
            <span className="text-accent-cyan">► {event.tool}</span>
          </div>
          {event.output && (
            <pre className="mt-1 text-xs text-text-secondary overflow-x-auto">{event.output}</pre>
          )}
        </div>
      )
    case 'approval':
      return (
        <div className="mx-3 my-1 px-3 py-2 rounded-md bg-bg-tertiary border border-accent-yellow">
          <div className="text-xs text-accent-yellow">{event.prompt}</div>
        </div>
      )
    case 'completion':
      return <div className="px-3 py-2 text-sm text-accent-green">✓ {event.summary}</div>
  }
}

export function TerminalPane({ events }: TerminalPaneProps) {
  return (
    <div className="flex-1 overflow-y-auto bg-bg-primary">
      {events.length === 0 ? (
        <div className="flex items-center justify-center h-full text-text-muted text-sm">
          Waiting for output...
        </div>
      ) : (
        events.map((event, i) => <EventItem key={i} event={event} />)
      )}
    </div>
  )
}
