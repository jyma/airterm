interface Shortcut {
  readonly label: string
  readonly command: string
  readonly danger?: boolean
}

const DEFAULT_SHORTCUTS: readonly Shortcut[] = [
  { label: 'y', command: 'y' },
  { label: '/commit', command: '/commit' },
  { label: '/review', command: '/review' },
  { label: '继续', command: '继续' },
  { label: 'Ctrl+C', command: '\x03', danger: true },
]

interface QuickPanelProps {
  readonly onSend: (command: string) => void
  readonly shortcuts?: readonly Shortcut[]
}

export function QuickPanel({ onSend, shortcuts = DEFAULT_SHORTCUTS }: QuickPanelProps) {
  return (
    <div className="flex gap-1.5 overflow-x-auto no-scrollbar">
      {shortcuts.map((s) => (
        <button
          key={s.label}
          onClick={() => onSend(s.command)}
          className={`shrink-0 px-3 py-1 rounded-md font-mono text-xs font-medium transition-opacity active:opacity-60 ${
            s.danger
              ? 'bg-accent-red/15 text-accent-red'
              : 'bg-bg-tertiary text-text-secondary'
          }`}
        >
          {s.label}
        </button>
      ))}
    </div>
  )
}
