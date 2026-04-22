import { getShortcuts, type Shortcut } from '@/lib/shortcuts'

interface QuickPanelProps {
  readonly onSend: (command: string) => void
  readonly shortcuts?: readonly Shortcut[]
}

function haptic(): void {
  if ('vibrate' in navigator) {
    navigator.vibrate(10)
  }
}

export function QuickPanel({ onSend, shortcuts }: QuickPanelProps) {
  const items = shortcuts ?? getShortcuts()

  return (
    <div className="flex gap-2 overflow-x-auto no-scrollbar py-0.5" style={{ WebkitOverflowScrolling: 'touch' }}>
      {items.map((s) => (
        <button
          key={s.label}
          onClick={() => { haptic(); onSend(s.command) }}
          className={`shrink-0 px-3.5 py-1.5 rounded-full font-[family-name:var(--font-mono)] text-xs font-medium transition-all active:scale-95 ${
            s.danger
              ? 'bg-accent-red/10 text-accent-red'
              : 'bg-bg-tertiary text-text-secondary hover:text-text-primary'
          }`}
        >
          {s.label}
        </button>
      ))}
    </div>
  )
}
