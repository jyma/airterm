import type { SequencedMessage, RelayEnvelope } from '@airterm/protocol'
import { createRelayEnvelope } from '@airterm/protocol'
import type { BusinessMessage } from '@airterm/protocol'
import type { CryptoLayer } from './crypto-layer.js'

export type ConnectionState = 'connecting' | 'connected' | 'disconnected'

export interface WSClientOptions {
  readonly url: string
  readonly token: string
  readonly deviceId: string
  readonly targetDeviceId: string
  readonly onMessage: (msg: SequencedMessage) => void
  readonly onStateChange: (state: ConnectionState) => void
  readonly cryptoLayer?: CryptoLayer | null
}

export interface WSClient {
  connect(): void
  disconnect(): void
  send(msg: BusinessMessage): void
  getState(): ConnectionState
}

const RECONNECT_DELAYS = [0, 1000, 3000, 10000, 30000]
const MAX_RECONNECT_ATTEMPTS = 100

export function createWSClient(options: WSClientOptions): WSClient {
  let ws: WebSocket | null = null
  let state: ConnectionState = 'disconnected'
  let reconnectAttempt = 0
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null
  let seq = 0
  let lastAck = 0
  let intentionalClose = false

  function setState(newState: ConnectionState): void {
    if (state !== newState) {
      state = newState
      options.onStateChange(newState)
    }
  }

  function encodeMessage(msg: SequencedMessage): string {
    const json = JSON.stringify(msg)
    if (options.cryptoLayer?.isActive) {
      return options.cryptoLayer.encryptPayload(json)
    }
    return btoa(json)
  }

  function decodeMessage(payload: string): SequencedMessage {
    if (options.cryptoLayer?.isActive) {
      const json = options.cryptoLayer.decryptPayload(payload)
      return JSON.parse(json) as SequencedMessage
    }
    return JSON.parse(atob(payload)) as SequencedMessage
  }

  function connect(): void {
    if (ws?.readyState === WebSocket.OPEN || ws?.readyState === WebSocket.CONNECTING) {
      return
    }

    intentionalClose = false
    setState('connecting')

    const separator = options.url.includes('?') ? '&' : '?'
    ws = new WebSocket(`${options.url}${separator}token=${options.token}`)

    ws.onopen = () => {
      setState('connected')
      reconnectAttempt = 0
    }

    ws.onmessage = (event) => {
      try {
        const envelope = JSON.parse(event.data as string) as RelayEnvelope
        if (envelope.type === 'relay' && envelope.payload) {
          const sequenced = decodeMessage(envelope.payload)
          lastAck = Math.max(lastAck, sequenced.seq)
          options.onMessage(sequenced)
        }
      } catch {
        // Skip unparseable messages
      }
    }

    ws.onclose = () => {
      ws = null
      setState('disconnected')
      if (!intentionalClose) {
        scheduleReconnect()
      }
    }

    ws.onerror = () => {
      // onclose will fire after onerror
    }
  }

  function disconnect(): void {
    intentionalClose = true
    clearReconnectTimer()
    ws?.close(1000, 'Client disconnect')
    ws = null
    setState('disconnected')
  }

  function send(msg: BusinessMessage): void {
    if (!ws || ws.readyState !== WebSocket.OPEN) return

    seq++
    const sequenced: SequencedMessage = { seq, ack: lastAck, message: msg }
    const payload = encodeMessage(sequenced)
    const envelope = createRelayEnvelope(options.deviceId, options.targetDeviceId, payload)
    ws.send(JSON.stringify(envelope))
  }

  function scheduleReconnect(): void {
    if (reconnectAttempt >= MAX_RECONNECT_ATTEMPTS) return

    const delayIndex = Math.min(reconnectAttempt, RECONNECT_DELAYS.length - 1)
    const delay = RECONNECT_DELAYS[delayIndex]
    reconnectAttempt++

    reconnectTimer = setTimeout(connect, delay)
  }

  function clearReconnectTimer(): void {
    if (reconnectTimer) {
      clearTimeout(reconnectTimer)
      reconnectTimer = null
    }
  }

  return {
    connect,
    disconnect,
    send,
    getState: () => state,
  }
}
