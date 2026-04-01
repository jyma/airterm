interface ApprovalBarProps {
  readonly sessionId: string
  readonly prompt: string
  readonly onApprove: (sessionId: string) => void
  readonly onDeny: (sessionId: string) => void
}

export function ApprovalBar({ sessionId, prompt, onApprove, onDeny }: ApprovalBarProps) {
  return (
    <div className="flex items-center gap-3 px-4 py-3 bg-bg-secondary border-t border-accent-yellow">
      <div className="flex-1 text-xs text-accent-yellow truncate">{prompt}</div>
      <button
        onClick={() => onDeny(sessionId)}
        className="px-4 h-10 rounded-lg bg-accent-red/20 text-accent-red text-sm font-medium hover:bg-accent-red/30 active:scale-95 transition-all"
      >
        Deny
      </button>
      <button
        onClick={() => onApprove(sessionId)}
        className="px-4 h-10 rounded-lg bg-accent-green/20 text-accent-green text-sm font-medium hover:bg-accent-green/30 active:scale-95 transition-all"
      >
        Allow
      </button>
    </div>
  )
}
