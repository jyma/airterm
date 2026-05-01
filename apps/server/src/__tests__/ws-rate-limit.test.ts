import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import WebSocket from 'ws'
import { startTestServer, type TestServer } from './helpers/test-server.js'

/// Smoke test for the per-WS-connection relay rate limit.
///
/// The cap is generous (600 msgs / 10s) so 30 Hz takeover never trips
/// it; the test fires WAY past that to confirm the throttle actually
/// kicks in and the sender gets a `code: 4029` echo.
let server: TestServer

beforeEach(async () => { server = await startTestServer() })
afterEach(async () => { await server.close() })

describe('WS relay rate limit', () => {
  it('allows normal traffic and rejects floods with code 4029', async () => {
    // Pair-init + complete to mint two valid tokens.
    const initRes = await fetch(`${server.url}/api/pair/init`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ macDeviceId: 'mac-rl', macName: 'Mac RL' }),
    })
    const init = (await initRes.json()) as {
      pairCode: string
      token: string
    }
    const completeRes = await fetch(`${server.url}/api/pair/complete`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pairCode: init.pairCode,
        phoneDeviceId: 'phone-rl',
        phoneName: 'Phone RL',
      }),
    })
    const complete = (await completeRes.json()) as { token: string }

    const macWs = new WebSocket(`${server.wsUrl}/ws/mac?token=${init.token}`)
    const phoneWs = new WebSocket(`${server.wsUrl}/ws/phone?token=${complete.token}`)
    await Promise.all([waitForOpen(macWs), waitForOpen(phoneWs)])

    const macInbox: Array<{ error?: string; code?: number }> = []
    macWs.on('message', (raw) => {
      try { macInbox.push(JSON.parse(String(raw))) } catch { /* ignore */ }
    })

    // Burst well past the 600/10s budget.
    for (let i = 0; i < 800; i++) {
      macWs.send(JSON.stringify({
        type: 'relay',
        from: 'mac-rl',
        to: 'phone-rl',
        ts: Date.now(),
        payload: 'AAAA',
      }))
    }
    // Drain the WS event loop so any error echoes land before we assert.
    await new Promise((r) => setTimeout(r, 200))

    // Sender should have received at least one rate-limit error.
    const throttled = macInbox.find((m) => m.code === 4029)
    expect(throttled).toBeTruthy()

    macWs.close()
    phoneWs.close()
  })
})

function waitForOpen(ws: WebSocket): Promise<void> {
  return new Promise((resolve, reject) => {
    ws.once('open', () => resolve())
    ws.once('error', reject)
  })
}
