/**
 * Format a timestamp as relative time in Chinese.
 */
export function formatRelativeTime(ts: number): string {
  const diff = Date.now() - ts
  const seconds = Math.floor(diff / 1000)

  if (seconds < 10) return '刚刚'
  if (seconds < 60) return `${seconds} 秒前`

  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes} 分钟前`

  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours} 小时前`

  const days = Math.floor(hours / 24)
  if (days < 30) return `${days} 天前`

  return new Date(ts).toLocaleDateString('zh-CN', { month: 'short', day: 'numeric' })
}
