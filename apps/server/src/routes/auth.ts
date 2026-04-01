import { Hono } from 'hono'
import type { JWTService } from '../auth/jwt.js'
import type { DeviceRepository } from '../db/devices.js'

export interface AuthRouteDeps {
  readonly jwtService: JWTService
  readonly devices: DeviceRepository
}

export function createAuthRoutes(deps: AuthRouteDeps): Hono {
  const app = new Hono()

  // Refresh access token
  app.post('/api/auth/refresh', async (c) => {
    const body = await c.req.json<{ refreshToken: string }>()
    if (!body.refreshToken) {
      return c.json({ error: 'refreshToken is required' }, 400)
    }

    const tokens = deps.jwtService.refresh(body.refreshToken)
    if (!tokens) {
      return c.json({ error: 'Invalid or expired refresh token' }, 401)
    }

    return c.json(tokens)
  })

  // Revoke a device (mac-side admin action)
  app.delete('/api/devices/:deviceId', async (c) => {
    const auth = c.req.header('Authorization')
    if (!auth?.startsWith('Bearer ')) {
      return c.json({ error: 'Unauthorized' }, 401)
    }

    const payload = deps.jwtService.verify(auth.slice(7))
    if (!payload || payload.role !== 'mac') {
      return c.json({ error: 'Unauthorized' }, 401)
    }

    const targetId = c.req.param('deviceId')
    deps.jwtService.revoke(targetId)
    deps.devices.delete(targetId)

    return c.json({ success: true })
  })

  return app
}
