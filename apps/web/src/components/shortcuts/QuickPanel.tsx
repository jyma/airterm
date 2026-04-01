interface Shortcut {
  readonly label: string
  readonly command: string
  readonly danger?: boolean
}

const DEFAULT_SHORTCUTS: readonly Shortcut[] = [
  { label: 'y', command: 'y' },
  { label: 'n', command: 'n' },
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
    <div className="flex gap-2 px-4 py-2 overflow-x-auto no-scrollbar">
      {shortcuts.map((s) => (
        <button
          key={s.label}
          onClick={() => onSend(s.command)}
          className={`shrink-0 px-3 py-1.5 rounded-full text-xs font-medium transition-all active:scale-95 ${
            s.danger
              ? 'bg-accent-red/15 text-accent-red hover:bg-accent-red/25'
              : 'bg-bg-tertiary text-text-secondary hover:text-text-primary hover:bg-border'
          }`}
        >
          {s.label}
        </button>
      ))}
    </div>
  )
}
