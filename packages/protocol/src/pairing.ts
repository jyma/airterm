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

export interface QRCodePayload {
  readonly server: string
  readonly pairCode: string
  readonly macDeviceId: string
  readonly macPublicKey?: string
}
