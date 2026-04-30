// ---- Pairing API types ----

export interface PairInitRequest {
  readonly macDeviceId: string
  readonly macName: string
}

export interface PairInitResponse {
  readonly pairId: string
  readonly pairCode: string
  readonly expiresAt: number
}

export interface PairCompleteRequest {
  readonly pairCode: string
  readonly phoneDeviceId: string
  readonly phoneName: string
  readonly phonePublicKey?: string
}

export interface PairCompleteResponse {
  readonly token: string
  readonly macDeviceId: string
  readonly macName: string
  readonly macPublicKey?: string
}

// Mac receives this via WebSocket when phone completes pairing
export interface PairCompletedNotification {
  readonly type: 'pair_completed'
  readonly phoneDeviceId: string
  readonly phoneName: string
  readonly token: string
  readonly phonePublicKey?: string
}

// ---- QR code content ----
//
// Two versions live side-by-side so older builds can still parse v1 QRs.
// New Mac builds emit v2 with the Noise IK static public key required so
// the phone (the IK initiator) has the responder static it needs to start
// the handshake. v1 is kept only for the inflight migration window —
// servers stop minting v1 once all production Macs are on v2.

export interface QRCodePayloadV1 {
  readonly v?: 1
  readonly server: string
  readonly pairCode: string
  readonly macDeviceId: string
  readonly macPublicKey?: string
}

export interface QRCodePayloadV2 {
  readonly v: 2
  readonly server: string
  readonly pairCode: string
  readonly macDeviceId: string
  /// 32-byte X25519 public key, base64url-encoded. Phone uses this as the
  /// responder's static key when starting the Noise IK handshake.
  readonly macPublicKey: string
}

export type QRCodePayload = QRCodePayloadV1 | QRCodePayloadV2

/// Returns true when the QR has the v2 fields the Noise IK initiator needs.
/// Lets call-sites pre-validate before they hand the payload to the
/// pairing flow.
export function isQRCodePayloadV2(qr: QRCodePayload): qr is QRCodePayloadV2 {
  return qr.v === 2 && typeof qr.macPublicKey === 'string' && qr.macPublicKey.length > 0
}
