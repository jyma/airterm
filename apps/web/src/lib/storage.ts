const PAIRING_KEY = 'airterm-pairing'

export interface PairingInfo {
  readonly token: string
  readonly deviceId: string
  readonly targetDeviceId: string
  readonly targetName: string
  readonly serverUrl: string
}

export function getStoredPairing(): PairingInfo | null {
  try {
    const raw = localStorage.getItem(PAIRING_KEY)
    if (!raw) return null
    return JSON.parse(raw) as PairingInfo
  } catch {
    return null
  }
}

export function storePairing(info: PairingInfo): void {
  localStorage.setItem(PAIRING_KEY, JSON.stringify(info))
}

export function clearPairing(): void {
  localStorage.removeItem(PAIRING_KEY)
}
