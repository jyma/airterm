import { describe, it, expect } from 'vitest'
import { createRateLimiter } from '../utils/rate-limit.js'

describe('Rate Limiter', () => {
  it('allows requests within the limit', () => {
    const limiter = createRateLimiter(3, 60_000)
    expect(limiter.check('ip-1')).toBe(true)
    expect(limiter.check('ip-1')).toBe(true)
    expect(limiter.check('ip-1')).toBe(true)
  })

  it('blocks requests exceeding the limit', () => {
    const limiter = createRateLimiter(2, 60_000)
    expect(limiter.check('ip-1')).toBe(true)
    expect(limiter.check('ip-1')).toBe(true)
    expect(limiter.check('ip-1')).toBe(false)
  })

  it('tracks different keys independently', () => {
    const limiter = createRateLimiter(1, 60_000)
    expect(limiter.check('ip-1')).toBe(true)
    expect(limiter.check('ip-1')).toBe(false)
    expect(limiter.check('ip-2')).toBe(true)
  })

  it('returns correct remaining count', () => {
    const limiter = createRateLimiter(3, 60_000)
    expect(limiter.remaining('ip-1')).toBe(3)
    limiter.check('ip-1')
    expect(limiter.remaining('ip-1')).toBe(2)
    limiter.check('ip-1')
    expect(limiter.remaining('ip-1')).toBe(1)
    limiter.check('ip-1')
    expect(limiter.remaining('ip-1')).toBe(0)
  })

  it('resets the limit for a key', () => {
    const limiter = createRateLimiter(1, 60_000)
    limiter.check('ip-1')
    expect(limiter.check('ip-1')).toBe(false)
    limiter.reset('ip-1')
    expect(limiter.check('ip-1')).toBe(true)
  })

  it('returns max remaining for unknown keys', () => {
    const limiter = createRateLimiter(5, 60_000)
    expect(limiter.remaining('unknown')).toBe(5)
  })
})
