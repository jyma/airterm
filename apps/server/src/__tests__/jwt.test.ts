import { describe, it, expect, beforeEach } from 'vitest'
import { createJWTService, type JWTService } from '../auth/jwt.js'

describe('JWT Service', () => {
  let jwt: JWTService

  beforeEach(() => {
    jwt = createJWTService('test-secret-that-is-at-least-32-chars-long')
  })

  it('generates a token pair with access and refresh tokens', () => {
    const pair = jwt.generatePair('device-1', 'mac')
    expect(pair.accessToken).toBeTruthy()
    expect(pair.refreshToken).toBeTruthy()
    expect(pair.accessToken).not.toBe(pair.refreshToken)
  })

  it('verifies a valid access token', () => {
    const pair = jwt.generatePair('device-1', 'mac')
    const payload = jwt.verify(pair.accessToken)
    expect(payload).not.toBeNull()
    expect(payload!.deviceId).toBe('device-1')
    expect(payload!.role).toBe('mac')
    expect(payload!.type).toBe('access')
  })

  it('verifies a valid refresh token', () => {
    const pair = jwt.generatePair('device-2', 'phone')
    const payload = jwt.verify(pair.refreshToken)
    expect(payload).not.toBeNull()
    expect(payload!.deviceId).toBe('device-2')
    expect(payload!.role).toBe('phone')
    expect(payload!.type).toBe('refresh')
  })

  it('rejects an invalid token', () => {
    expect(jwt.verify('invalid-token')).toBeNull()
    expect(jwt.verify('')).toBeNull()
    expect(jwt.verify('a.b.c')).toBeNull()
  })

  it('rejects a tampered token', () => {
    const pair = jwt.generatePair('device-1', 'mac')
    const tampered = pair.accessToken.slice(0, -2) + 'XX'
    expect(jwt.verify(tampered)).toBeNull()
  })

  it('refreshes a valid refresh token', () => {
    const pair = jwt.generatePair('device-1', 'mac')
    const newPair = jwt.refresh(pair.refreshToken)
    expect(newPair).not.toBeNull()
    expect(newPair!.accessToken).toBeTruthy()
    expect(newPair!.refreshToken).toBeTruthy()
    // Verify the new access token is valid
    const payload = jwt.verify(newPair!.accessToken)
    expect(payload).not.toBeNull()
    expect(payload!.deviceId).toBe('device-1')
    expect(payload!.type).toBe('access')
  })

  it('does not refresh an access token', () => {
    const pair = jwt.generatePair('device-1', 'mac')
    expect(jwt.refresh(pair.accessToken)).toBeNull()
  })

  it('revokes a device and rejects its tokens', () => {
    const pair = jwt.generatePair('device-1', 'mac')
    expect(jwt.verify(pair.accessToken)).not.toBeNull()

    jwt.revoke('device-1')

    expect(jwt.isRevoked('device-1')).toBe(true)
    expect(jwt.verify(pair.accessToken)).toBeNull()
    expect(jwt.verify(pair.refreshToken)).toBeNull()
  })

  it('does not revoke unrelated devices', () => {
    const pair1 = jwt.generatePair('device-1', 'mac')
    const pair2 = jwt.generatePair('device-2', 'phone')

    jwt.revoke('device-1')

    expect(jwt.verify(pair1.accessToken)).toBeNull()
    expect(jwt.verify(pair2.accessToken)).not.toBeNull()
  })
})
