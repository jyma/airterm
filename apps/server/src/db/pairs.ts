import type Database from 'better-sqlite3'

export interface PairRow {
  readonly id: string
  readonly mac_device_id: string
  readonly phone_device_id: string | null
  readonly pair_code: string
  readonly status: 'pending' | 'completed' | 'expired'
  readonly attempts: number
  readonly created_at: number
  readonly expires_at: number
}

export interface PairRepository {
  findById(id: string): PairRow | undefined
  findByCode(code: string): PairRow | undefined
  findByDevices(macId: string, phoneId: string): PairRow | undefined
  findActivePairsByMac(macId: string): PairRow[]
  create(pair: Pick<PairRow, 'id' | 'mac_device_id' | 'pair_code' | 'expires_at'>): PairRow
  complete(id: string, phoneDeviceId: string): void
  incrementAttempts(id: string): void
  expire(id: string): void
  isPaired(macId: string, phoneId: string): boolean
  /** Counts of pair rows by status. Used by /metrics. */
  countByStatus(): { pending: number; completed: number; expired: number }
}

export function createPairRepository(db: Database.Database): PairRepository {
  const findByIdStmt = db.prepare<[string], PairRow>('SELECT * FROM pairs WHERE id = ?')
  const findByCodeStmt = db.prepare<[string], PairRow>(
    "SELECT * FROM pairs WHERE pair_code = ? AND status = 'pending'",
  )
  const findByDevicesStmt = db.prepare<[string, string], PairRow>(
    "SELECT * FROM pairs WHERE mac_device_id = ? AND phone_device_id = ? AND status = 'completed'",
  )
  const findActivePairsByMacStmt = db.prepare<[string], PairRow>(
    "SELECT * FROM pairs WHERE mac_device_id = ? AND status = 'completed'",
  )
  const insertStmt = db.prepare(
    'INSERT INTO pairs (id, mac_device_id, pair_code, expires_at) VALUES (@id, @mac_device_id, @pair_code, @expires_at)',
  )
  const completeStmt = db.prepare(
    "UPDATE pairs SET phone_device_id = ?, status = 'completed' WHERE id = ?",
  )
  const incrementAttemptsStmt = db.prepare('UPDATE pairs SET attempts = attempts + 1 WHERE id = ?')
  const expireStmt = db.prepare("UPDATE pairs SET status = 'expired' WHERE id = ?")
  const isPairedStmt = db.prepare<[string, string], { count: number }>(
    "SELECT COUNT(*) as count FROM pairs WHERE mac_device_id = ? AND phone_device_id = ? AND status = 'completed'",
  )
  const countByStatusStmt = db.prepare<[], { status: string; n: number }>(
    'SELECT status, COUNT(*) AS n FROM pairs GROUP BY status'
  )

  return {
    findById(id) {
      return findByIdStmt.get(id)
    },

    findByCode(code) {
      return findByCodeStmt.get(code)
    },

    findByDevices(macId, phoneId) {
      return findByDevicesStmt.get(macId, phoneId)
    },

    findActivePairsByMac(macId) {
      return findActivePairsByMacStmt.all(macId)
    },

    create(pair) {
      insertStmt.run(pair)
      return findByIdStmt.get(pair.id)!
    },

    complete(id, phoneDeviceId) {
      completeStmt.run(phoneDeviceId, id)
    },

    incrementAttempts(id) {
      incrementAttemptsStmt.run(id)
    },

    expire(id) {
      expireStmt.run(id)
    },

    isPaired(macId, phoneId) {
      const row = isPairedStmt.get(macId, phoneId)
      return (row?.count ?? 0) > 0
    },

    countByStatus() {
      const out = { pending: 0, completed: 0, expired: 0 }
      for (const row of countByStatusStmt.all()) {
        if (row.status === 'pending' || row.status === 'completed' || row.status === 'expired') {
          out[row.status] = row.n
        }
      }
      return out
    },
  }
}
