/**
 * Lightweight Markdown-to-HTML for Claude messages.
 * Handles: **bold**, *italic*, `code`, [links](url), and ```code blocks```
 * No external dependencies.
 */

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function processInline(text: string): string {
  let result = escapeHtml(text)

  // Code spans: `code`
  result = result.replace(/`([^`]+)`/g, '<code class="bg-bg-tertiary px-1 py-0.5 rounded text-[13px] font-[family-name:var(--font-mono)]">$1</code>')

  // Bold: **text**
  result = result.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')

  // Italic: *text*
  result = result.replace(/\*([^*]+)\*/g, '<em>$1</em>')

  // Links: [text](url)
  result = result.replace(
    /\[([^\]]+)\]\(([^)]+)\)/g,
    '<a href="$2" target="_blank" rel="noopener noreferrer" class="text-accent-blue underline">$1</a>',
  )

  return result
}

export function renderMarkdown(text: string): string {
  const lines = text.split('\n')
  const result: string[] = []
  let inCodeBlock = false
  let codeLines: string[] = []
  for (const line of lines) {
    if (line.startsWith('```')) {
      if (inCodeBlock) {
        result.push(
          `<div class="bg-bg-tertiary rounded-md p-2 my-1 overflow-x-auto font-[family-name:var(--font-mono)] text-xs leading-relaxed">${codeLines.map(escapeHtml).join('\n')}</div>`,
        )
        codeLines = []
        inCodeBlock = false
      } else {
        inCodeBlock = true
      }
      continue
    }

    if (inCodeBlock) {
      codeLines.push(line)
      continue
    }

    // List items: - item or * item
    if (/^[-*] /.test(line)) {
      result.push(`<div class="pl-3">• ${processInline(line.slice(2))}</div>`)
      continue
    }

    // Numbered list: 1. item
    if (/^\d+\. /.test(line)) {
      const match = line.match(/^(\d+)\. (.*)$/)
      if (match) {
        result.push(`<div class="pl-3">${match[1]}. ${processInline(match[2])}</div>`)
        continue
      }
    }

    // Empty line → paragraph break
    if (line.trim() === '') {
      result.push('<div class="h-2"></div>')
      continue
    }

    // Regular paragraph
    result.push(`<div>${processInline(line)}</div>`)
  }

  // Handle unclosed code block
  if (inCodeBlock && codeLines.length > 0) {
    result.push(
      `<div class="bg-bg-tertiary rounded-md p-2 my-1 overflow-x-auto font-[family-name:var(--font-mono)] text-xs leading-relaxed">${codeLines.map(escapeHtml).join('\n')}</div>`,
    )
  }

  return result.join('')
}
