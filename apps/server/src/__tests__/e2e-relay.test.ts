import { describe, it, expect, beforeAll } from 'vitest'

const SERVER_URL = 'http://8.218.78.18'
const WS_URL = 'ws://8.218.78.18'

describe('E2E: WebSocket Message Relay', () => {
  let phoneToken: string

  beforeAll(async () => {
    const macId = `relay-mac-${Date.now()}`
    const phoneId = `relay-phone-${Date.now()}`

    const initRes = await fetch(`${SERVER_URL}/api/pair/init`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ macDeviceId: macId, macName: 'Relay Mac' }),
    })
    const { pairCode } = await initRes.json()

    const completeRes = await fetch(`${SERVER_URL}/api/pair/complete`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pairCode, phoneDeviceId: phoneId, phoneName: 'Relay Phone' }),
    })
    phoneToken = (await completeRes.json()).token
  })

  it('Phone can connect via WebSocket with valid token', async () => {
    const ws = new WebSocket(`${WS_URL}/ws/phone?token=${phoneToken}`)

    const opened = await new Promise<boolean>((resolve) => {
      const timeout = setTimeout(() => resolve(false), 5000)
      ws.onopen = () => {
        clearTimeout(timeout)
        resolve(true)
      }
      ws.onerror = () => {
        clearTimeout(timeout)
        resolve(false)
      }
    })

    expect(opened).toBe(true)
    ws.close()
  })

  it('WebSocket with invalid token is rejected', async () => {
    const ws = new WebSocket(`${WS_URL}/ws/phone?token=invalid-token`)

    const result = await new Promise<'error' | 'open'>((resolve) => {
      const timeout = setTimeout(() => resolve('error'), 5000)
      ws.onopen = () => {
        clearTimeout(timeout)
        ws.close()
        resolve('open')
      }
      ws.onerror = () => {
        clearTimeout(timeout)
        resolve('error')
      }
    })

    // Invalid token should be rejected at HTTP level (401), not upgraded to WS
    expect(result).toBe('error')
  })

  it('Phone can send messages after connecting', async () => {
    const ws = new WebSocket(`${WS_URL}/ws/phone?token=${phoneToken}`)

    await new Promise<void>((resolve) => {
      ws.onopen = () => resolve()
    })

    // Send a message (will get error since mac isn't connected, but shouldn't crash)
    const message = JSON.stringify({
      type: 'relay',
      from: 'phone-test',
      to: 'mac-nonexistent',
      ts: Date.now(),
      payload: btoa(JSON.stringify({ kind: 'ping' })),
    })

    // Should not throw
    ws.send(message)

    // Wait for any response
    const response = await new Promise<string | null>((resolve) => {
      const timeout = setTimeout(() => resolve(null), 2000)
      ws.onmessage = (event) => {
        clearTimeout(timeout)
        resolve(event.data as string)
      }
    })

    // Should get an error response (target offline or not paired)
    if (response) {
      const parsed = JSON.parse(response)
      expect(parsed.error).toBeTruthy()
    }

    ws.close()
  })
}, 20000)
