import Database from 'better-sqlite3'

export function createDatabase(dbPath: string): Database.Database {
  const db = new Database(dbPath)

  db.pragma('journal_mode = WAL')
  db.pragma('foreign_keys = ON')

  db.exec(`
    CREATE TABLE IF NOT EXISTS devices (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      role TEXT NOT NULL CHECK (role IN ('mac', 'phone')),
      token TEXT,
      created_at INTEGER NOT NULL DEFAULT (unixepoch()),
      last_seen_at INTEGER
    );

    CREATE TABLE IF NOT EXISTS pairs (
      id TEXT PRIMARY KEY,
      mac_device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
      phone_device_id TEXT REFERENCES devices(id) ON DELETE CASCADE,
      pair_code TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'expired')),
      attempts INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL DEFAULT (unixepoch()),
      expires_at INTEGER NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_pairs_code ON pairs(pair_code);
    CREATE INDEX IF NOT EXISTS idx_pairs_mac ON pairs(mac_device_id);
    CREATE INDEX IF NOT EXISTS idx_pairs_phone ON pairs(phone_device_id);
  `)

  return db
}
