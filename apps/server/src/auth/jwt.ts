import { createHmac } from 'node:crypto'

export interface JWTPayload {
  readonly deviceId: string
  readonly role: 'mac' | 'phone'
  readonly type: 'access' | 'refresh'
  readonly iat: number
  readonly exp: number
}

export interface TokenPair {
  readonly accessToken: string
  readonly refreshToken: string
}

const ACCESS_TOKEN_TTL = 15 * 60 // 15 minutes
const REFRESH_TOKEN_TTL = 30 * 24 * 60 * 60 // 30 days

export interface JWTService {
  generatePair(deviceId: string, role: 'mac' | 'phone'): TokenPair
  verify(token: string): JWTPayload | null
  refresh(refreshToken: string): TokenPair | null
  revoke(deviceId: string): void
  isRevoked(deviceId: string): boolean
}

export function createJWTService(secret: string): JWTService {
  const revokedDevices = new Set<string>()

  function sign(payload: JWTPayload): string {
    const data = JSON.stringify(payload)
    const encoded = Buffer.from(data).toString('base64url')
    const signature = createHmac('sha256', secret).update(encoded).digest('base64url')
    return `${encoded}.${signature}`
  }

  function verify(token: string): JWTPayload | null {
    const parts = token.split('.')
    if (parts.length !== 2) return null

    const [encoded, signature] = parts
    const expected = createHmac('sha256', secret).update(encoded).digest('base64url')
    if (signature !== expected) return null

    try {
      const payload = JSON.parse(Buffer.from(encoded, 'base64url').toString()) as JWTPayload

      // Check expiration
      const now = Math.floor(Date.now() / 1000)
      if (payload.exp && payload.exp < now) return null

      // Check revocation
      if (revokedDevices.has(payload.deviceId)) return null

      return payload
    } catch {
      return null
    }
  }

  return {
    generatePair(deviceId, role) {
      const now = Math.floor(Date.now() / 1000)
      const accessPayload: JWTPayload = {
        deviceId,
        role,
        type: 'access',
        iat: now,
        exp: now + ACCESS_TOKEN_TTL,
      }
      const refreshPayload: JWTPayload = {
        deviceId,
        role,
        type: 'refresh',
        iat: now,
        exp: now + REFRESH_TOKEN_TTL,
      }
      return {
        accessToken: sign(accessPayload),
        refreshToken: sign(refreshPayload),
      }
    },

    verify,

    refresh(refreshToken) {
      const payload = verify(refreshToken)
      if (!payload || payload.type !== 'refresh') return null
      return this.generatePair(payload.deviceId, payload.role)
    },

    revoke(deviceId) {
      revokedDevices.add(deviceId)
    },

    isRevoked(deviceId) {
      return revokedDevices.has(deviceId)
    },
  }
}
