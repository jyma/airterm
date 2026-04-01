const PAIRING_KEY = 'airterm-pairing'

export interface PairingInfo {
  readonly token: string
  readonly deviceId: string
  readonly targetDeviceId: string
  readonly targetName: string
  readonly serverUrl: string
}

function isValidPairing(v: unknown): v is PairingInfo {
  if (typeof v !== 'object' || v === null) return false
  const o = v as Record<string, unknown>
  return (
    typeof o.token === 'string' &&
    o.token.length > 0 &&
    typeof o.deviceId === 'string' &&
    o.deviceId.length > 0 &&
    typeof o.targetDeviceId === 'string' &&
    o.targetDeviceId.length > 0 &&
    typeof o.targetName === 'string' &&
    typeof o.serverUrl === 'string' &&
    o.serverUrl.length > 0
  )
}

export function getStoredPairing(): PairingInfo | null {
  try {
    const raw = localStorage.getItem(PAIRING_KEY)
    if (!raw) return null
    const parsed: unknown = JSON.parse(raw)
    if (!isValidPairing(parsed)) {
      localStorage.removeItem(PAIRING_KEY)
      return null
    }
    return parsed
  } catch {
    localStorage.removeItem(PAIRING_KEY)
    return null
  }
}

export function storePairing(info: PairingInfo): void {
  localStorage.setItem(PAIRING_KEY, JSON.stringify(info))
}

export function clearPairing(): void {
  localStorage.removeItem(PAIRING_KEY)
}
