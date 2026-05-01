import type { SequencedMessage } from '@airterm/protocol'
import type { SignalingMessage } from '@airterm/protocol'
import { NoisePairDriver, NoisePairDriverError } from './noise-pair-driver'
import {
  PairClientError,
  completePair,
  getDefaultPhoneName,
  getOrCreatePhoneDeviceId,
  parseQRPayload,
} from './pair-client'
import { loadOrCreatePhoneIdentity } from './phone-identity'
import { createWSClient, type WSClient } from './ws-client'
import type { PairingInfo } from './storage'
import { TakeoverChannel } from './takeover-channel'

/// Result of a successful phone-side pair flow. Carries the persisted
/// `pairingInfo` (caller stores it) plus the live transport — the
/// TakeoverChannel + the warm WSClient — so the UI can render the
/// takeover view without re-handshaking.
export interface PairFlowResult {
  readonly pairingInfo: PairingInfo
  readonly channel: TakeoverChannel
  readonly ws: WSClient
}

/// Top-level orchestrator for the phone-side pair flow.
///   1. Parse the QR payload (v2 only — needs `macPublicKey`).
///   2. POST /api/pair/complete to get a phone JWT and the Mac device id.
///   3. Load (or generate) the phone's persistent X25519 static keypair.
///   4. Open a WS to the relay tagged as `phone`.
///   5. Once connected, start the IK initiator (writeMessageA).
///   6. On the responder's stage-2 frame, finalise the handshake and
///      resolve with a `PairingInfo` ready for storage.
///
/// On any failure (network, AEAD, malformed QR, timeout) the WS is torn
/// down before the promise rejects so we never leak a half-open
/// connection. A 30-second safety timeout caps the worst case.
export async function runPhonePairFlow(rawQR: string): Promise<PairFlowResult> {
  const qr = parseQRPayload(rawQR)
  const phoneDeviceId = getOrCreatePhoneDeviceId()
  const phoneName = getDefaultPhoneName()
  const completeResult = await completePair(qr, phoneDeviceId, phoneName)
  const phoneIdentity = await loadOrCreatePhoneIdentity()

  return new Promise<PairFlowResult>((resolve, reject) => {
    let settled = false
    const safetyTimer = setTimeout(() => fail(new PairClientError(
      'timeout',
      'Pairing timed out before the Noise handshake completed.'
    )), 30_000)

    function fail(error: unknown): void {
      if (settled) return
      settled = true
      clearTimeout(safetyTimer)
      try { ws.disconnect() } catch { /* ws may not be open yet */ }
      reject(error)
    }

    function succeed(result: PairFlowResult): void {
      if (settled) return
      settled = true
      clearTimeout(safetyTimer)
      // Don't disconnect — the takeover layer takes over the WS.
      resolve(result)
    }

    let driver: NoisePairDriver
    let channelRef: TakeoverChannel | null = null
    try {
      driver = new NoisePairDriver({
        qr,
        phoneStaticKeyPair: phoneIdentity.keyPair,
        sendFrame: (frame) => {
          // Wrap the NoiseHandshakeFrame in a SignalingMessage so the
          // Mac's signaling router (PairingWindow.handleSignalingMessage)
          // routes it to its NoisePairResponder.
          ws.send(frame as SignalingMessage)
        },
      })
    } catch (e) {
      reject(e)
      clearTimeout(safetyTimer)
      return
    }

    const ws = createWSClient({
      url: wsURLFor(qr.server, 'phone'),
      token: completeResult.token,
      deviceId: phoneDeviceId,
      targetDeviceId: completeResult.macDeviceId,
      onStateChange: (state) => {
        if (state === 'connected') {
          try {
            driver.start()
          } catch (e) {
            fail(e)
          }
        }
      },
      onMessage: (sequenced: SequencedMessage) => {
        // The opaque BusinessMessage carries our SignalingMessage. Pre-
        // handshake we expect Noise frames; once the channel exists we
        // route encrypted frames into it instead.
        const inner = sequenced.message as SignalingMessage
        if (channelRef && channelRef.handleIncoming(inner)) {
          return
        }
        try {
          const out = driver.processIncomingMessage(inner)
          if (out.done && out.result) {
            // Build the long-lived TakeoverChannel from the transport
            // CipherStates the handshake just produced. From here on,
            // every encrypted frame the WS forwards belongs to it.
            channelRef = new TakeoverChannel({
              send: out.result.send,
              receive: out.result.receive,
              sendSignaling: (msg) => ws.send(msg as SignalingMessage),
              onFrame: () => { /* installed by caller via onChannelFrame */ },
              onError: () => { /* same */ },
            })
            const pairingInfo: PairingInfo = {
              token: completeResult.token,
              deviceId: phoneDeviceId,
              targetDeviceId: completeResult.macDeviceId,
              targetName: completeResult.macName,
              serverUrl: completeResult.serverUrl,
              pairedAt: Date.now(),
              macPublicKey: completeResult.macPublicKey,
            }
            succeed({ pairingInfo, channel: channelRef, ws })
          }
        } catch (e) {
          fail(
            e instanceof NoisePairDriverError
              ? e
              : new NoisePairDriverError(
                  'inbound_handler_failed',
                  e instanceof Error ? e.message : String(e)
                )
          )
        }
      },
    })

    ws.connect()
  })
}

/// Converts an http(s) relay base URL into the corresponding ws(s)
/// endpoint for the role-specific WS path the relay exposes.
export function wsURLFor(serverHttpURL: string, role: 'phone' | 'mac'): string {
  const wsBase = serverHttpURL
    .replace(/^https:\/\//, 'wss://')
    .replace(/^http:\/\//, 'ws://')
  // Tolerate a trailing slash on the configured server URL.
  const trimmed = wsBase.endsWith('/') ? wsBase.slice(0, -1) : wsBase
  return `${trimmed}/ws/${role}`
}
