import WebSocket from 'ws'

export interface MockDevice {
  readonly deviceId: string
  readonly token: string
  readonly role: 'mac' | 'phone'
  readonly messages: unknown[]
  connect(wsUrl: string): Promise<void>
  waitForMessage(
    predicate: (msg: unknown) => boolean,
    timeoutMs?: number,
  ): Promise<unknown>
  sendRelay(to: string, message: Record<string, unknown>): void
  sendRaw(data: string): void
  close(): Promise<void>
}

export function createMockDevice(
  deviceId: string,
  token: string,
  role: 'mac' | 'phone',
): MockDevice {
  let ws: WebSocket | null = null
  let seq = 0
  const messages: unknown[] = []
  const waiters: Array<{
    predicate: (msg: unknown) => boolean
    resolve: (msg: unknown) => void
  }> = []

  return {
    deviceId,
    token,
    role,
    messages,

    connect(wsUrl: string): Promise<void> {
      return new Promise((resolve, reject) => {
        const endpoint = `${wsUrl}/ws/${role}?token=${token}`
        ws = new WebSocket(endpoint)

        const timeout = setTimeout(() => {
          reject(new Error(`Connection timeout for ${role}:${deviceId.slice(0, 8)}`))
        }, 5000)

        ws.on('open', () => {
          clearTimeout(timeout)
          resolve()
        })

        ws.on('error', (err) => {
          clearTimeout(timeout)
          reject(err)
        })

        ws.on('message', (raw) => {
          try {
            const data = JSON.parse(String(raw))
            messages.push(data)

            // Check pending waiters
            for (let i = waiters.length - 1; i >= 0; i--) {
              if (waiters[i].predicate(data)) {
                const waiter = waiters.splice(i, 1)[0]
                waiter.resolve(data)
              }
            }
          } catch {
            // skip unparseable
          }
        })
      })
    },

    waitForMessage(
      predicate: (msg: unknown) => boolean,
      timeoutMs = 5000,
    ): Promise<unknown> {
      // Check already received messages first
      const existing = messages.find(predicate)
      if (existing) return Promise.resolve(existing)

      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          const idx = waiters.findIndex((w) => w.resolve === resolve)
          if (idx >= 0) waiters.splice(idx, 1)
          reject(new Error(`waitForMessage timeout after ${timeoutMs}ms`))
        }, timeoutMs)

        waiters.push({
          predicate,
          resolve: (msg) => {
            clearTimeout(timer)
            resolve(msg)
          },
        })
      })
    },

    sendRelay(to: string, message: Record<string, unknown>): void {
      if (!ws || ws.readyState !== WebSocket.OPEN) {
        throw new Error('WebSocket not connected')
      }
      seq++
      const sequenced = { seq, ack: 0, message }
      const payload = Buffer.from(JSON.stringify(sequenced)).toString('base64')
      const envelope = {
        type: 'relay',
        from: deviceId,
        to,
        ts: Date.now(),
        payload,
      }
      ws.send(JSON.stringify(envelope))
    },

    sendRaw(data: string): void {
      if (!ws || ws.readyState !== WebSocket.OPEN) {
        throw new Error('WebSocket not connected')
      }
      ws.send(data)
    },

    close(): Promise<void> {
      return new Promise((resolve) => {
        if (!ws || ws.readyState === WebSocket.CLOSED) {
          resolve()
          return
        }
        let settled = false
        const finish = () => {
          if (!settled) {
            settled = true
            resolve()
          }
        }
        ws.once('close', finish)
        ws.close(1000)
        setTimeout(finish, 2000)
      })
    },
  }
}

export interface PairResult {
  readonly macId: string
  readonly phoneId: string
  readonly macToken: string
  readonly phoneToken: string
}

export async function pairDevices(serverUrl: string): Promise<PairResult> {
  const macId = `mac-${crypto.randomUUID()}`
  const phoneId = `phone-${crypto.randomUUID()}`

  const initRes = await fetch(`${serverUrl}/api/pair/init`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ macDeviceId: macId, macName: 'Test Mac' }),
  })
  if (!initRes.ok) {
    throw new Error(`pair/init failed: ${initRes.status} ${await initRes.text()}`)
  }
  const { pairCode, token: macToken } = await initRes.json()

  const completeRes = await fetch(`${serverUrl}/api/pair/complete`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      pairCode,
      phoneDeviceId: phoneId,
      phoneName: 'Test Phone',
    }),
  })
  if (!completeRes.ok) {
    throw new Error(`pair/complete failed: ${completeRes.status} ${await completeRes.text()}`)
  }
  const { token: phoneToken } = await completeRes.json()

  return { macId, phoneId, macToken, phoneToken }
}

/** Decode a relay envelope's payload into a SequencedMessage */
export function decodeRelayPayload(envelope: {
  type: string
  payload?: string
}): { seq: number; ack: number; message: Record<string, unknown> } | null {
  if (envelope.type !== 'relay' || !envelope.payload) return null
  try {
    return JSON.parse(Buffer.from(envelope.payload, 'base64').toString('utf-8'))
  } catch {
    return null
  }
}
