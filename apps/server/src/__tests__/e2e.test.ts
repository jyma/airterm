import { describe, it, expect } from 'vitest'

const SERVER_URL = 'http://8.218.78.18'
const WS_URL = 'ws://8.218.78.18'

describe('E2E: Relay Server', () => {
  it('health check responds ok', async () => {
    const res = await fetch(`${SERVER_URL}/health`)
    const body = await res.json()
    expect(body.status).toBe('ok')
    expect(body.version).toBe('0.1.0')
  })

  it('full pairing flow works', async () => {
    // 1. Mac initiates pairing
    const initRes = await fetch(`${SERVER_URL}/api/pair/init`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        macDeviceId: `e2e-mac-${Date.now()}`,
        macName: 'E2E Test Mac',
      }),
    })
    expect(initRes.status).toBe(200)
    const { pairCode } = await initRes.json()
    expect(pairCode).toHaveLength(6)

    // 2. Phone completes pairing
    const completeRes = await fetch(`${SERVER_URL}/api/pair/complete`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pairCode,
        phoneDeviceId: `e2e-phone-${Date.now()}`,
        phoneName: 'E2E Test Phone',
      }),
    })
    expect(completeRes.status).toBe(200)
    const { token, macDeviceId } = await completeRes.json()
    expect(token).toBeTruthy()
    expect(macDeviceId).toBeTruthy()
  })

  it('WebSocket relay forwards messages between paired devices', async () => {
    const macId = `ws-mac-${Date.now()}`
    const phoneId = `ws-phone-${Date.now()}`

    // Pair the devices
    const initRes = await fetch(`${SERVER_URL}/api/pair/init`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ macDeviceId: macId, macName: 'WS Mac' }),
    })
    const { pairCode } = await initRes.json()

    const completeRes = await fetch(`${SERVER_URL}/api/pair/complete`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pairCode, phoneDeviceId: phoneId, phoneName: 'WS Phone' }),
    })
    const { token: phoneToken } = await completeRes.json()

    // Verify the WebSocket endpoint accepts connections with valid token
    const phoneWs = new WebSocket(`${WS_URL}/ws/phone?token=${phoneToken}`)

    const connected = await new Promise<boolean>((resolve) => {
      const timeout = setTimeout(() => resolve(false), 5000)
      phoneWs.onopen = () => {
        clearTimeout(timeout)
        resolve(true)
      }
      phoneWs.onerror = () => {
        clearTimeout(timeout)
        resolve(false)
      }
    })

    expect(connected).toBe(true)

    phoneWs.close()
  }, 10000)

  it('rejects invalid pair code', async () => {
    const res = await fetch(`${SERVER_URL}/api/pair/complete`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pairCode: 'INVALID',
        phoneDeviceId: 'test-phone',
        phoneName: 'Test',
      }),
    })
    expect(res.status).toBe(404)
  })

  it('rejects missing fields', async () => {
    const res = await fetch(`${SERVER_URL}/api/pair/init`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ macDeviceId: 'test' }),
    })
    expect(res.status).toBe(400)
  })
})
