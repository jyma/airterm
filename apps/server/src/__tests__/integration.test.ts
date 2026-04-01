import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { Hono } from 'hono'
import { createDatabase } from '../db/init.js'
import { createDeviceRepository } from '../db/devices.js'
import { createPairRepository } from '../db/pairs.js'
import { createTokenService } from '../auth/token.js'
import { createWSManager } from '../ws/manager.js'
import { createHealthRoutes } from '../routes/health.js'
import { createPairRoutes } from '../routes/pair.js'
import type { Config } from '../config.js'
import type Database from 'better-sqlite3'

const TEST_SECRET = 'test-secret-that-is-at-least-32-chars-long!'

let db: Database.Database
let app: Hono

beforeEach(() => {
  db = createDatabase(':memory:')
  const devices = createDeviceRepository(db)
  const pairs = createPairRepository(db)
  const tokenService = createTokenService(TEST_SECRET)
  const wsManager = createWSManager({ tokenService, devices, pairs })
  const config: Config = {
    port: 3000,
    jwtSecret: TEST_SECRET,
    pairCodeTtl: 300,
    dbPath: ':memory:',
    domain: 'localhost',
  }

  app = new Hono()
  app.route('/', createHealthRoutes())
  app.route('/', createPairRoutes({ devices, pairs, tokenService, config, wsManager }))
})

afterEach(() => {
  db.close()
})

describe('GET /health', () => {
  it('returns ok status', async () => {
    const res = await app.request('/health')
    expect(res.status).toBe(200)

    const body = await res.json()
    expect(body.status).toBe('ok')
    expect(body.version).toBe('0.1.0')
    expect(body.timestamp).toBeGreaterThan(0)
  })
})

describe('POST /api/pair/init', () => {
  it('creates a pair and returns code', async () => {
    const res = await app.request('/api/pair/init', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ macDeviceId: 'mac-1', macName: 'My Mac' }),
    })

    expect(res.status).toBe(200)
    const body = await res.json()
    expect(body.pairId).toBeTruthy()
    expect(body.pairCode).toBeTruthy()
    expect(body.pairCode).toHaveLength(6)
    expect(body.expiresAt).toBeGreaterThan(0)
  })

  it('rejects missing fields', async () => {
    const res = await app.request('/api/pair/init', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ macDeviceId: 'mac-1' }),
    })

    expect(res.status).toBe(400)
  })
})

describe('POST /api/pair/complete', () => {
  it('completes pairing successfully', async () => {
    // Init pairing
    const initRes = await app.request('/api/pair/init', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ macDeviceId: 'mac-1', macName: 'My Mac' }),
    })
    const { pairCode } = await initRes.json()

    // Complete pairing
    const res = await app.request('/api/pair/complete', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pairCode,
        phoneDeviceId: 'phone-1',
        phoneName: 'My Phone',
      }),
    })

    expect(res.status).toBe(200)
    const body = await res.json()
    expect(body.token).toBeTruthy()
    expect(body.macDeviceId).toBe('mac-1')
    expect(body.macName).toBe('My Mac')
  })

  it('rejects invalid pair code', async () => {
    const res = await app.request('/api/pair/complete', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pairCode: 'INVALID',
        phoneDeviceId: 'phone-1',
        phoneName: 'My Phone',
      }),
    })

    expect(res.status).toBe(404)
  })

  it('rejects after max attempts', async () => {
    const initRes = await app.request('/api/pair/init', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ macDeviceId: 'mac-1', macName: 'My Mac' }),
    })
    const { pairCode } = await initRes.json()

    // Exhaust attempts with wrong phone IDs (each attempt increments counter)
    for (let i = 0; i < 3; i++) {
      await app.request('/api/pair/complete', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          pairCode,
          phoneDeviceId: `phone-${i}`,
          phoneName: `Phone ${i}`,
        }),
      })
    }

    // 4th attempt should fail
    const res = await app.request('/api/pair/complete', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pairCode,
        phoneDeviceId: 'phone-final',
        phoneName: 'Final Phone',
      }),
    })

    // Code should be expired/invalid after max attempts
    expect([404, 429]).toContain(res.status)
  })

  it('rejects missing fields', async () => {
    const res = await app.request('/api/pair/complete', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pairCode: 'ABC123' }),
    })

    expect(res.status).toBe(400)
  })
})
