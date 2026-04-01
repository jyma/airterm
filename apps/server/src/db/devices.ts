import type Database from 'better-sqlite3'

export interface DeviceRow {
  readonly id: string
  readonly name: string
  readonly role: 'mac' | 'phone'
  readonly token: string | null
  readonly created_at: number
  readonly last_seen_at: number | null
}

export interface DeviceRepository {
  findById(id: string): DeviceRow | undefined
  findByToken(token: string): DeviceRow | undefined
  create(device: Pick<DeviceRow, 'id' | 'name' | 'role'>): DeviceRow
  updateToken(id: string, token: string): void
  updateLastSeen(id: string): void
  delete(id: string): boolean
}

export function createDeviceRepository(db: Database.Database): DeviceRepository {
  const findByIdStmt = db.prepare<[string], DeviceRow>('SELECT * FROM devices WHERE id = ?')
  const findByTokenStmt = db.prepare<[string], DeviceRow>('SELECT * FROM devices WHERE token = ?')
  const insertStmt = db.prepare('INSERT INTO devices (id, name, role) VALUES (@id, @name, @role)')
  const updateTokenStmt = db.prepare('UPDATE devices SET token = ? WHERE id = ?')
  const updateLastSeenStmt = db.prepare(
    'UPDATE devices SET last_seen_at = unixepoch() WHERE id = ?',
  )
  const deleteStmt = db.prepare('DELETE FROM devices WHERE id = ?')

  return {
    findById(id) {
      return findByIdStmt.get(id)
    },

    findByToken(token) {
      return findByTokenStmt.get(token)
    },

    create(device) {
      insertStmt.run(device)
      return findByIdStmt.get(device.id)!
    },

    updateToken(id, token) {
      updateTokenStmt.run(token, id)
    },

    updateLastSeen(id) {
      updateLastSeenStmt.run(id)
    },

    delete(id) {
      const result = deleteStmt.run(id)
      return result.changes > 0
    },
  }
}
