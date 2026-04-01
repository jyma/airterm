interface ApprovalBarProps {
  readonly sessionId: string
  readonly prompt: string
  readonly command?: string
  readonly onApprove: (sessionId: string) => void
  readonly onDeny: (sessionId: string) => void
}

export function ApprovalBar({ sessionId, prompt, command, onApprove, onDeny }: ApprovalBarProps) {
  return (
    <div className="mx-3.5 mb-2 bg-bg-secondary rounded-lg p-3 space-y-2.5">
      <div className="font-mono text-xs text-accent-yellow">⚠ {prompt}</div>

      {command && (
        <div className="bg-bg-tertiary rounded-md px-2.5 py-1.5">
          <span className="font-mono text-xs text-text-primary">{command}</span>
        </div>
      )}

      <div className="flex gap-2.5">
        <button
          onClick={() => onDeny(sessionId)}
          className="flex-1 h-10 rounded-lg bg-bg-tertiary font-[family-name:var(--font-ui)] text-sm font-semibold text-accent-red active:opacity-70 transition-opacity"
          aria-label="Deny"
        >
          Deny
        </button>
        <button
          onClick={() => onApprove(sessionId)}
          className="flex-1 h-10 rounded-lg bg-accent-blue font-[family-name:var(--font-ui)] text-sm font-semibold text-white active:opacity-70 transition-opacity"
          aria-label="Allow"
        >
          Allow
        </button>
      </div>
    </div>
  )
}
