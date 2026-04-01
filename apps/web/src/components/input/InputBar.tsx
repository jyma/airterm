import { useRef, useCallback, useState } from 'react'

interface InputBarProps {
  readonly onSend: (text: string) => void
  readonly disabled?: boolean
}

export function InputBar({ onSend, disabled = false }: InputBarProps) {
  const [text, setText] = useState('')
  const [sending, setSending] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  const handleSubmit = useCallback(
    (e: React.FormEvent) => {
      e.preventDefault()
      if (!text.trim() || disabled || sending) return
      setSending(true)
      onSend(text)
      setText('')
      // Brief visual feedback
      setTimeout(() => {
        setSending(false)
        inputRef.current?.focus()
      }, 300)
    },
    [text, disabled, sending, onSend],
  )

  return (
    <form onSubmit={handleSubmit} className="flex gap-2 items-center">
      <div className="flex-1 flex items-center bg-bg-tertiary rounded-[18px] px-3.5 h-[38px]">
        <input
          ref={inputRef}
          type="text"
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Send a message..."
          disabled={disabled}
          className="flex-1 bg-transparent text-[13px] text-text-primary font-[family-name:var(--font-ui)] placeholder:text-text-muted focus:outline-none"
        />
      </div>
      <button
        type="submit"
        disabled={!text.trim() || disabled || sending}
        className={`w-[38px] h-[38px] shrink-0 rounded-full text-white flex items-center justify-center disabled:opacity-30 transition-all ${
          sending ? 'bg-accent-green scale-90' : 'bg-accent-blue active:opacity-70'
        }`}
        aria-label="Send"
      >
        {sending ? (
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="20 6 9 17 4 12" />
          </svg>
        ) : (
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
            <line x1="12" y1="19" x2="12" y2="5" />
            <polyline points="5 12 12 5 19 12" />
          </svg>
        )}
      </button>
    </form>
  )
}
