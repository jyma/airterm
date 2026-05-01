export interface Config {
  readonly port: number
  readonly jwtSecret: string
  readonly pairCodeTtl: number
  readonly dbPath: string
  readonly domain: string
}

export function loadConfig(): Config {
  const jwtSecret = process.env.JWT_SECRET
  if (!jwtSecret || jwtSecret.length < 32) {
    throw new Error('JWT_SECRET must be set and at least 32 characters')
  }

  return {
    port: parseInt(process.env.PORT ?? '3000', 10),
    jwtSecret,
    pairCodeTtl: parseInt(process.env.PAIR_CODE_TTL ?? '300', 10),
    // Prefer the AIRTERM-namespaced env var so a Fly / Railway / k8s
    // deploy holding multiple databases doesn't accidentally clash with
    // another service's `DB_PATH`. Fall back to the legacy var so
    // existing local `.env` files keep working.
    dbPath: process.env.AIRTERM_DB_PATH ?? process.env.DB_PATH ?? './airterm.db',
    domain: process.env.DOMAIN ?? 'localhost',
  }
}
