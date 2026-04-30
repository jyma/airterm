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
import { createWSClient } from './ws-client'
import type { PairingInfo } from './storage'

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
export async function runPhonePairFlow(rawQR: string): Promise<PairingInfo> {
  const qr = parseQRPayload(rawQR)
  const phoneDeviceId = getOrCreatePhoneDeviceId()
  const phoneName = getDefaultPhoneName()
  const completeResult = await completePair(qr, phoneDeviceId, phoneName)
  const phoneIdentity = await loadOrCreatePhoneIdentity()

  return new Promise<PairingInfo>((resolve, reject) => {
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

    function succeed(info: PairingInfo): void {
      if (settled) return
      settled = true
      clearTimeout(safetyTimer)
      try { ws.disconnect() } catch { /* ws may already be closed */ }
      resolve(info)
    }

    let driver: NoisePairDriver
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
        // handshake we expect only Noise frames; anything else is a
        // protocol violation.
        const inner = sequenced.message as SignalingMessage
        try {
          const out = driver.processIncomingMessage(inner)
          if (out.done) {
            succeed({
              token: completeResult.token,
              deviceId: phoneDeviceId,
              targetDeviceId: completeResult.macDeviceId,
              targetName: completeResult.macName,
              serverUrl: completeResult.serverUrl,
              pairedAt: Date.now(),
              macPublicKey: completeResult.macPublicKey,
            })
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
