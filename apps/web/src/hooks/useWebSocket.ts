import { useState, useEffect, useRef, useCallback } from 'react'
import { createWSClient, type WSClient, type ConnectionState } from '@/lib/ws-client'
import type { BusinessMessage, SequencedMessage } from '@airterm/protocol'
import type { CryptoLayer } from '@/lib/crypto-layer'

export interface UseWebSocketOptions {
  readonly url: string
  readonly token: string
  readonly deviceId: string
  readonly targetDeviceId: string
  readonly onMessage?: (msg: SequencedMessage) => void
  readonly cryptoLayer?: CryptoLayer | null
}

export interface UseWebSocketReturn {
  readonly state: ConnectionState
  readonly send: (msg: BusinessMessage) => void
  readonly connect: () => void
  readonly disconnect: () => void
}

export function useWebSocket(options: UseWebSocketOptions): UseWebSocketReturn {
  const [state, setState] = useState<ConnectionState>('disconnected')
  const clientRef = useRef<WSClient | null>(null)
  const onMessageRef = useRef(options.onMessage)
  onMessageRef.current = options.onMessage

  useEffect(() => {
    const client = createWSClient({
      url: options.url,
      token: options.token,
      deviceId: options.deviceId,
      targetDeviceId: options.targetDeviceId,
      onMessage: (msg) => onMessageRef.current?.(msg),
      onStateChange: setState,
      cryptoLayer: options.cryptoLayer,
    })

    clientRef.current = client
    client.connect()

    return () => {
      client.disconnect()
      clientRef.current = null
    }
  }, [options.url, options.token, options.deviceId, options.targetDeviceId, options.cryptoLayer])

  const send = useCallback((msg: BusinessMessage) => {
    clientRef.current?.send(msg)
  }, [])

  const connect = useCallback(() => {
    clientRef.current?.connect()
  }, [])

  const disconnect = useCallback(() => {
    clientRef.current?.disconnect()
  }, [])

  return { state, send, connect, disconnect }
}
