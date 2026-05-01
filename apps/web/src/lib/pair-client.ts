import {
  isQRCodePayloadV2,
  type QRCodePayload,
  type QRCodePayloadV2,
} from '@airterm/protocol'

/// Fields the phone needs from the pair-complete response. Mirrors the
/// server's response body shape from `apps/server/src/routes/pair.ts`.
interface PairCompleteResponseBody {
  readonly token: string
  readonly macDeviceId: string
  readonly macName: string
}

/// Result of a successful POST /api/pair/complete + parse round trip.
/// Returned to the page so it can persist + redirect.
export interface PairResult {
  readonly token: string
  readonly macDeviceId: string
  readonly macName: string
  readonly serverUrl: string
  readonly macPublicKey: string
}

export class PairClientError extends Error {
  constructor(readonly code: string, message: string) {
    super(message)
    this.name = 'PairClientError'
  }
}

/// Decodes a scanned QR payload string into a typed QR payload. Accepts
/// only v2 — v1 is rejected because the Noise IK initiator (the phone)
/// requires the responder's static public key to start the handshake.
export function parseQRPayload(raw: string): QRCodePayloadV2 {
  let parsed: QRCodePayload
  try {
    parsed = JSON.parse(raw) as QRCodePayload
  } catch {
    throw new PairClientError('qr_invalid_json', 'QR code is not valid JSON.')
  }
  if (!isQRCodePayloadV2(parsed)) {
    throw new PairClientError(
      'qr_unsupported_version',
      'QR code is missing the v2 fields (macPublicKey). Update the Mac app.'
    )
  }
  if (!/^https?:\/\//.test(parsed.server)) {
    throw new PairClientError('qr_bad_server', 'QR server URL is not http(s).')
  }
  return parsed
}

/// POST /api/pair/complete with the pair code and the phone's identity.
/// Throws PairClientError with a stable code on every non-2xx so the UI
/// can surface a precise message.
export async function completePair(
  qr: QRCodePayloadV2,
  phoneDeviceId: string,
  phoneName: string
): Promise<PairResult> {
  let response: Response
  try {
    response = await fetch(`${qr.server}/api/pair/complete`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pairCode: qr.pairCode,
        phoneDeviceId,
        phoneName,
      }),
    })
  } catch {
    throw new PairClientError(
      'network',
      `Could not reach the relay server at ${qr.server}.`
    )
  }

  if (!response.ok) {
    let message = `Server returned HTTP ${response.status}.`
    try {
      const body = (await response.json()) as { error?: string }
      if (typeof body.error === 'string') message = body.error
    } catch {
      // body wasn't JSON; fall back to the status-only message
    }
    throw new PairClientError(`http_${response.status}`, message)
  }

  let body: PairCompleteResponseBody
  try {
    body = (await response.json()) as PairCompleteResponseBody
  } catch {
    throw new PairClientError('bad_response', 'Server response was not JSON.')
  }
  if (!body.token || !body.macDeviceId) {
    throw new PairClientError(
      'bad_response',
      'Server response is missing token / macDeviceId.'
    )
  }

  return {
    token: body.token,
    macDeviceId: body.macDeviceId,
    macName: body.macName ?? 'Mac',
    serverUrl: qr.server,
    macPublicKey: qr.macPublicKey,
  }
}

/// Generates a stable per-browser device id and persists it. Good enough
/// for MVP — spec says phone identity may be ephemeral if the user reinstalls.
export function getOrCreatePhoneDeviceId(): string {
  const KEY = 'airterm.phoneDeviceId'
  const existing = localStorage.getItem(KEY)
  if (existing) return existing
  const fresh =
    typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : `web-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`
  localStorage.setItem(KEY, fresh)
  return fresh
}

/// Best-effort phone name. The user can refine it from a Settings page
/// later; for MVP we read what the browser tells us.
export function getDefaultPhoneName(): string {
  const ua = navigator.userAgent
  if (/iPhone/i.test(ua)) return 'iPhone (web)'
  if (/iPad/i.test(ua)) return 'iPad (web)'
  if (/Android/i.test(ua)) return 'Android (web)'
  return 'Browser'
}
