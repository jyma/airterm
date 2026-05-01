import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { startTestServer, type TestServer } from './helpers/test-server.js'

let server: TestServer
beforeEach(async () => { server = await startTestServer() })
afterEach(async () => { await server.close() })

/// /health is the liveness probe — minimal payload, always 200, no
/// auth gate. /health/detailed + /metrics expose operational counts
/// behind an optional bearer (HEALTH_TOKEN env), so a public
/// scraper can't enumerate paired devices.
describe('GET /health', () => {
  it('returns the small liveness payload', async () => {
    const res = await fetch(`${server.url}/health`)
    expect(res.status).toBe(200)
    const body = (await res.json()) as { status?: string; version?: string }
    expect(body.status).toBe('ok')
    expect(body.version).toBe('0.1.0')
  })
})

describe('GET /health/detailed', () => {
  it('exposes connection / device / pair counts', async () => {
    const res = await fetch(`${server.url}/health/detailed`)
    expect(res.status).toBe(200)
    const body = await res.json() as {
      connections: { mac: number; phone: number; total: number }
      devices: { mac: number; phone: number }
      pairs: { pending: number; completed: number; expired: number }
      uptimeMs: number
    }
    expect(body.connections.total).toBeGreaterThanOrEqual(0)
    expect(body.connections.mac).toBeGreaterThanOrEqual(0)
    expect(body.connections.phone).toBeGreaterThanOrEqual(0)
    expect(body.devices.mac).toBeGreaterThanOrEqual(0)
    expect(body.pairs.pending).toBeGreaterThanOrEqual(0)
    expect(body.uptimeMs).toBeGreaterThan(0)
  })

  it('reflects a freshly created pair record', async () => {
    await fetch(`${server.url}/api/pair/init`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ macDeviceId: 'mac-h', macName: 'Mac H' }),
    })
    const res = await fetch(`${server.url}/health/detailed`)
    const body = await res.json() as {
      devices: { mac: number; phone: number }
      pairs: { pending: number }
    }
    expect(body.devices.mac).toBe(1)
    expect(body.pairs.pending).toBe(1)
  })
})

describe('GET /metrics', () => {
  it('returns Prometheus text exposition with the four expected metrics', async () => {
    const res = await fetch(`${server.url}/metrics`)
    expect(res.status).toBe(200)
    expect(res.headers.get('content-type') ?? '').toMatch(/text\/plain/)
    const text = await res.text()
    expect(text).toContain('# HELP airterm_ws_connections')
    expect(text).toContain('# TYPE airterm_ws_connections gauge')
    expect(text).toMatch(/airterm_ws_connections\{role="mac"\}\s+\d+/)
    expect(text).toMatch(/airterm_ws_connections\{role="phone"\}\s+\d+/)
    expect(text).toContain('# HELP airterm_devices_total')
    expect(text).toContain('# HELP airterm_pairs_total')
    expect(text).toMatch(/airterm_uptime_seconds\s+\d+/)
  })
})
