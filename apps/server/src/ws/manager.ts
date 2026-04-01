import type { WebSocket } from 'ws'
import type { TokenService } from '../auth/token.js'
import type { DeviceRepository } from '../db/devices.js'
import type { PairRepository } from '../db/pairs.js'

export interface ConnectedDevice {
  readonly ws: WebSocket
  readonly deviceId: string
  readonly role: 'mac' | 'phone'
  lastPing: number
}

export interface WSManager {
  handleConnection(ws: WebSocket, token: string): void
  sendToDevice(deviceId: string, data: unknown): boolean
  getConnectedDevice(deviceId: string): ConnectedDevice | undefined
  getConnectionCount(): number
  startHeartbeat(): void
  stopHeartbeat(): void
  closeAll(): void
}

export interface WSManagerDeps {
  readonly tokenService: TokenService
  readonly devices: DeviceRepository
  readonly pairs: PairRepository
}

const HEARTBEAT_INTERVAL = 30_000
const HEARTBEAT_TIMEOUT = 90_000

export function createWSManager(deps: WSManagerDeps): WSManager {
  const connections = new Map<string, ConnectedDevice>()
  let heartbeatTimer: ReturnType<typeof setInterval> | null = null

  function handleConnection(ws: WebSocket, token: string): void {
    const payload = deps.tokenService.verify(token)
    if (!payload) {
      ws.close(4001, 'Invalid token')
      return
    }

    const device = deps.devices.findById(payload.deviceId)
    if (!device) {
      ws.close(4002, 'Device not found')
      return
    }

    // Close existing connection for this device
    const existing = connections.get(payload.deviceId)
    if (existing) {
      existing.ws.close(1000, 'Replaced by new connection')
    }

    const connected: ConnectedDevice = {
      ws,
      deviceId: payload.deviceId,
      role: payload.role,
      lastPing: Date.now(),
    }

    connections.set(payload.deviceId, connected)
    deps.devices.updateLastSeen(payload.deviceId)

    ws.on('message', (raw) => {
      handleMessage(connected, raw)
    })

    ws.on('close', () => {
      const current = connections.get(payload.deviceId)
      if (current?.ws === ws) {
        connections.delete(payload.deviceId)
      }
    })

    ws.on('pong', () => {
      connected.lastPing = Date.now()
    })
  }

  function handleMessage(sender: ConnectedDevice, raw: unknown): void {
    let data: { type?: string; from?: string; to?: string; payload?: string }
    try {
      data = JSON.parse(String(raw))
    } catch {
      return
    }

    if (data.type === 'relay' && data.to) {
      relayMessage(sender, data.to, raw)
    }
  }

  function relayMessage(sender: ConnectedDevice, targetId: string, raw: unknown): void {
    // Verify sender and target are paired
    const senderId = sender.deviceId
    const senderRole = sender.role

    const macId = senderRole === 'mac' ? senderId : targetId
    const phoneId = senderRole === 'phone' ? senderId : targetId

    if (!deps.pairs.isPaired(macId, phoneId)) {
      sender.ws.send(JSON.stringify({ error: 'Not paired with target device', code: 4002 }))
      return
    }

    const target = connections.get(targetId)
    if (!target || target.ws.readyState !== 1) {
      sender.ws.send(JSON.stringify({ error: 'Target device offline', code: 4004 }))
      return
    }

    // Forward raw message as-is
    target.ws.send(String(raw))
    deps.devices.updateLastSeen(senderId)
  }

  function sendToDevice(deviceId: string, data: unknown): boolean {
    const conn = connections.get(deviceId)
    if (!conn || conn.ws.readyState !== 1) return false
    conn.ws.send(JSON.stringify(data))
    return true
  }

  function startHeartbeat(): void {
    heartbeatTimer = setInterval(() => {
      const now = Date.now()
      for (const [id, conn] of connections) {
        if (now - conn.lastPing > HEARTBEAT_TIMEOUT) {
          conn.ws.terminate()
          connections.delete(id)
        } else {
          conn.ws.ping()
        }
      }
    }, HEARTBEAT_INTERVAL)
  }

  function stopHeartbeat(): void {
    if (heartbeatTimer) {
      clearInterval(heartbeatTimer)
      heartbeatTimer = null
    }
  }

  function closeAll(): void {
    stopHeartbeat()
    for (const conn of connections.values()) {
      conn.ws.close(1000, 'Server shutting down')
    }
    connections.clear()
  }

  return {
    handleConnection,
    sendToDevice,
    getConnectedDevice(deviceId) {
      return connections.get(deviceId)
    },
    getConnectionCount() {
      return connections.size
    },
    startHeartbeat,
    stopHeartbeat,
    closeAll,
  }
}
