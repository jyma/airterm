import type { SequencedMessage } from '@airterm/protocol'
import type { SignalingMessage } from '@airterm/protocol'
import { NoisePairDriver, NoisePairDriverError } from './noise-pair-driver'
import { loadOrCreatePhoneIdentity } from './phone-identity'
import { createWSClient } from './ws-client'
import type { PairingInfo } from './storage'
import { TakeoverChannel } from './takeover-channel'
import { wsURLFor, type PairFlowResult } from './pair-flow'

/// Phone-side reconnect flow. Called by `PairedPage` when the user
/// returns to a paired browser session — refresh, new tab, etc.
///
/// The HTTP pair-init / pair-complete handshake is one-shot per pair
/// code, but the JWT and the static keys both sides hold are
/// long-lived. So a reconnect is just:
///
///   1. Reload the persisted phone X25519 identity.
///   2. Open a fresh WS using the stored Mac-issued token.
///   3. Run a brand-new Noise IK handshake with the same responder
///      static key the QR delivered the first time. The Mac side
///      is listening for exactly this in PairingCoordinator.
///   4. On stage-2 success, install the live TakeoverChannel and
///      hand it back to the page so it can mount TakeoverViewer.
///
/// Throws `PairingInfoMissingFieldsError` if the stored pairing was
/// minted by a pre-v2 build that didn't capture macPublicKey — those
/// users have to re-pair manually because IK can't proceed without
/// the responder's static.
export class PairingInfoMissingFieldsError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'PairingInfoMissingFieldsError'
  }
}

export async function runPhoneReconnectFlow(
  stored: PairingInfo
): Promise<PairFlowResult> {
  if (!stored.macPublicKey) {
    throw new PairingInfoMissingFieldsError(
      'Stored pairing has no macPublicKey — re-pair to upgrade.'
    )
  }

  const phoneIdentity = await loadOrCreatePhoneIdentity()

  return new Promise<PairFlowResult>((resolve, reject) => {
    let settled = false
    const safetyTimer = setTimeout(() => fail(new NoisePairDriverError(
      'reconnect_timeout',
      'Reconnect timed out before the Noise handshake completed.'
    )), 15_000)

    function fail(error: unknown): void {
      if (settled) return
      settled = true
      clearTimeout(safetyTimer)
      try { ws.disconnect() } catch { /* not yet connected */ }
      reject(error)
    }

    function succeed(result: PairFlowResult): void {
      if (settled) return
      settled = true
      clearTimeout(safetyTimer)
      // WS keeps running — TakeoverChannel owns it now.
      resolve(result)
    }

    let driver: NoisePairDriver
    let channelRef: TakeoverChannel | null = null
    try {
      driver = new NoisePairDriver({
        qr: {
          v: 2,
          server: stored.serverUrl,
          // pairCode is unused on the reconnect path — leave a stub
          // so the v2 type guard still passes, but nothing reads it.
          pairCode: '',
          macDeviceId: stored.targetDeviceId,
          macPublicKey: stored.macPublicKey!,
        },
        phoneStaticKeyPair: phoneIdentity.keyPair,
        sendFrame: (frame) => {
          ws.send(frame as SignalingMessage)
        },
      })
    } catch (e) {
      reject(e)
      clearTimeout(safetyTimer)
      return
    }

    const ws = createWSClient({
      url: wsURLFor(stored.serverUrl, 'phone'),
      token: stored.token,
      deviceId: stored.deviceId,
      targetDeviceId: stored.targetDeviceId,
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
        const inner = sequenced.message as SignalingMessage
        if (channelRef && channelRef.handleIncoming(inner)) {
          return
        }
        try {
          const out = driver.processIncomingMessage(inner)
          if (out.done && out.result) {
            channelRef = new TakeoverChannel({
              send: out.result.send,
              receive: out.result.receive,
              sendSignaling: (msg) => ws.send(msg as SignalingMessage),
              onFrame: () => { /* parent installs */ },
              onError: () => { /* parent installs */ },
            })
            // Bump pairedAt so a "last seen" UI can render fresh.
            const refreshed: PairingInfo = {
              ...stored,
              pairedAt: Date.now(),
            }
            succeed({ pairingInfo: refreshed, channel: channelRef, ws })
          }
        } catch (e) {
          fail(e)
        }
      },
    })

    ws.connect()
  })
}
