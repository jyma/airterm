import { Hono } from 'hono'
import { randomUUID } from 'node:crypto'
import type { DeviceRepository } from '../db/devices.js'
import type { PairRepository } from '../db/pairs.js'
import type { TokenService } from '../auth/token.js'
import { generatePairCode } from '../utils/pair-code.js'
import type { Config } from '../config.js'
import type { WSManager } from '../ws/manager.js'

export interface PairRouteDeps {
  readonly devices: DeviceRepository
  readonly pairs: PairRepository
  readonly tokenService: TokenService
  readonly config: Config
  readonly wsManager: WSManager
}

const MAX_PAIR_ATTEMPTS = 3

export function createPairRoutes(deps: PairRouteDeps): Hono {
  const app = new Hono()

  // Mac initiates pairing — generates a pair code
  app.post('/api/pair/init', async (c) => {
    const body = await c.req.json<{ macDeviceId: string; macName: string }>()

    if (!body.macDeviceId || !body.macName) {
      return c.json({ error: 'macDeviceId and macName are required' }, 400)
    }

    // Upsert mac device
    let device = deps.devices.findById(body.macDeviceId)
    if (!device) {
      device = deps.devices.create({
        id: body.macDeviceId,
        name: body.macName,
        role: 'mac',
      })
    }

    const pairCode = generatePairCode()
    const expiresAt = Math.floor(Date.now() / 1000) + deps.config.pairCodeTtl

    const pair = deps.pairs.create({
      id: randomUUID(),
      mac_device_id: body.macDeviceId,
      pair_code: pairCode,
      expires_at: expiresAt,
    })

    // Generate mac token if not already
    let macToken = device.token
    if (!macToken) {
      macToken = deps.tokenService.generate(body.macDeviceId, 'mac')
      deps.devices.updateToken(body.macDeviceId, macToken)
    }

    return c.json({
      pairId: pair.id,
      pairCode: pair.pair_code,
      expiresAt: pair.expires_at,
      token: macToken,
    })
  })

  // Phone completes pairing — sends pair code + device info
  app.post('/api/pair/complete', async (c) => {
    const body = await c.req.json<{
      pairCode: string
      phoneDeviceId: string
      phoneName: string
    }>()

    if (!body.pairCode || !body.phoneDeviceId || !body.phoneName) {
      return c.json({ error: 'pairCode, phoneDeviceId, and phoneName are required' }, 400)
    }

    const pair = deps.pairs.findByCode(body.pairCode)

    if (!pair) {
      return c.json({ error: 'Invalid or expired pair code' }, 404)
    }

    // Check expiration
    if (pair.expires_at < Math.floor(Date.now() / 1000)) {
      deps.pairs.expire(pair.id)
      return c.json({ error: 'Pair code expired' }, 410)
    }

    // Check max attempts
    if (pair.attempts >= MAX_PAIR_ATTEMPTS) {
      deps.pairs.expire(pair.id)
      return c.json({ error: 'Too many attempts, pair code invalidated' }, 429)
    }

    deps.pairs.incrementAttempts(pair.id)

    // Create phone device if not exists
    if (!deps.devices.findById(body.phoneDeviceId)) {
      deps.devices.create({
        id: body.phoneDeviceId,
        name: body.phoneName,
        role: 'phone',
      })
    }

    // Generate phone token
    const token = deps.tokenService.generate(body.phoneDeviceId, 'phone')
    deps.devices.updateToken(body.phoneDeviceId, token)

    // Complete pairing
    deps.pairs.complete(pair.id, body.phoneDeviceId)

    // Notify Mac via WebSocket
    const macDevice = deps.devices.findById(pair.mac_device_id)
    deps.wsManager.sendToDevice(pair.mac_device_id, {
      type: 'pair_completed',
      phoneDeviceId: body.phoneDeviceId,
      phoneName: body.phoneName,
      token: deps.devices.findById(pair.mac_device_id)?.token ?? '',
    })

    return c.json({
      token,
      macDeviceId: pair.mac_device_id,
      macName: macDevice?.name ?? 'Unknown',
    })
  })

  return app
}
