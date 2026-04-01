import { describe, it, expect } from 'vitest'
import { createTokenService, generateDeviceId } from '../auth/token.js'

const SECRET = 'test-secret-that-is-at-least-32-chars-long!'

describe('TokenService', () => {
  const svc = createTokenService(SECRET)

  it('generates and verifies a token', () => {
    const token = svc.generate('device-1', 'mac')
    const payload = svc.verify(token)

    expect(payload).not.toBeNull()
    expect(payload!.deviceId).toBe('device-1')
    expect(payload!.role).toBe('mac')
    expect(payload!.iat).toBeGreaterThan(0)
  })

  it('rejects tampered tokens', () => {
    const token = svc.generate('device-1', 'mac')
    const tampered = token.slice(0, -1) + 'x'

    expect(svc.verify(tampered)).toBeNull()
  })

  it('rejects tokens signed with different secret', () => {
    const other = createTokenService('different-secret-that-is-at-least-32-chars!')
    const token = other.generate('device-1', 'mac')

    expect(svc.verify(token)).toBeNull()
  })

  it('rejects invalid format', () => {
    expect(svc.verify('')).toBeNull()
    expect(svc.verify('no-dot')).toBeNull()
    expect(svc.verify('a.b.c')).toBeNull()
  })
})

describe('generateDeviceId', () => {
  it('returns a 32-char hex string', () => {
    const id = generateDeviceId()
    expect(id).toMatch(/^[0-9a-f]{32}$/)
  })

  it('generates unique IDs', () => {
    const ids = new Set(Array.from({ length: 100 }, () => generateDeviceId()))
    expect(ids.size).toBe(100)
  })
})
