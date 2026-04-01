/**
 * Simple in-memory rate limiter.
 * Tracks request counts per key within a sliding window.
 */

interface RateLimitEntry {
  count: number
  resetAt: number
}

export interface RateLimiter {
  /** Check if the key is rate-limited. Returns true if allowed. */
  check(key: string): boolean
  /** Get remaining attempts for a key */
  remaining(key: string): number
  /** Reset the rate limit for a key */
  reset(key: string): void
}

export function createRateLimiter(
  maxRequests: number,
  windowMs: number,
): RateLimiter {
  const entries = new Map<string, RateLimitEntry>()

  // Cleanup expired entries periodically
  setInterval(() => {
    const now = Date.now()
    for (const [key, entry] of entries) {
      if (entry.resetAt <= now) {
        entries.delete(key)
      }
    }
  }, windowMs)

  return {
    check(key) {
      const now = Date.now()
      const entry = entries.get(key)

      if (!entry || entry.resetAt <= now) {
        entries.set(key, { count: 1, resetAt: now + windowMs })
        return true
      }

      if (entry.count >= maxRequests) {
        return false
      }

      entries.set(key, { ...entry, count: entry.count + 1 })
      return true
    },

    remaining(key) {
      const now = Date.now()
      const entry = entries.get(key)
      if (!entry || entry.resetAt <= now) return maxRequests
      return Math.max(0, maxRequests - entry.count)
    },

    reset(key) {
      entries.delete(key)
    },
  }
}
