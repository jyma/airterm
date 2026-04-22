import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto'

export interface TokenPayload {
  readonly deviceId: string
  readonly role: 'mac' | 'phone'
  readonly iat: number
}

export interface TokenService {
  generate(deviceId: string, role: 'mac' | 'phone'): string
  verify(token: string): TokenPayload | null
}

export function createTokenService(secret: string): TokenService {
  function sign(payload: TokenPayload): string {
    const data = JSON.stringify(payload)
    const encoded = Buffer.from(data).toString('base64url')
    const signature = createHmac('sha256', secret).update(encoded).digest('base64url')
    return `${encoded}.${signature}`
  }

  function verify(token: string): TokenPayload | null {
    const parts = token.split('.')
    if (parts.length !== 2) return null

    const [encoded, signature] = parts
    const expected = createHmac('sha256', secret).update(encoded).digest('base64url')

    const sigBuf = Buffer.from(signature)
    const expBuf = Buffer.from(expected)
    if (sigBuf.length !== expBuf.length || !timingSafeEqual(sigBuf, expBuf)) return null

    try {
      const data = Buffer.from(encoded, 'base64url').toString()
      return JSON.parse(data) as TokenPayload
    } catch {
      return null
    }
  }

  return {
    generate(deviceId, role) {
      const payload: TokenPayload = {
        deviceId,
        role,
        iat: Math.floor(Date.now() / 1000),
      }
      return sign(payload)
    },

    verify,
  }
}

export function generateDeviceId(): string {
  return randomBytes(16).toString('hex')
}
