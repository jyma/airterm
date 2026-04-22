/**
 * Persistent shortcut storage for QuickPanel.
 */

export interface Shortcut {
  readonly label: string
  readonly command: string
  readonly danger?: boolean
}

const STORAGE_KEY = 'airterm-shortcuts'

const DEFAULT_SHORTCUTS: readonly Shortcut[] = [
  { label: 'y', command: 'y' },
  { label: '/commit', command: '/commit' },
  { label: '/review', command: '/review' },
  { label: '继续', command: '继续' },
  { label: 'Ctrl+C', command: '\x03', danger: true },
]

export function getShortcuts(): readonly Shortcut[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return DEFAULT_SHORTCUTS
    const parsed = JSON.parse(raw) as Shortcut[]
    if (!Array.isArray(parsed) || parsed.length === 0) return DEFAULT_SHORTCUTS
    return parsed
  } catch {
    return DEFAULT_SHORTCUTS
  }
}

export function saveShortcuts(shortcuts: readonly Shortcut[]): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(shortcuts))
}

export function resetShortcuts(): void {
  localStorage.removeItem(STORAGE_KEY)
}

export { DEFAULT_SHORTCUTS }
