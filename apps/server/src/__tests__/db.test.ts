import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { createDatabase } from '../db/init.js'
import { createDeviceRepository } from '../db/devices.js'
import { createPairRepository } from '../db/pairs.js'
import type Database from 'better-sqlite3'

let db: Database.Database

beforeEach(() => {
  db = createDatabase(':memory:')
})

afterEach(() => {
  db.close()
})

describe('DeviceRepository', () => {
  it('creates and finds a device', () => {
    const repo = createDeviceRepository(db)
    const device = repo.create({ id: 'mac-1', name: 'My Mac', role: 'mac' })

    expect(device.id).toBe('mac-1')
    expect(device.name).toBe('My Mac')
    expect(device.role).toBe('mac')
    expect(device.token).toBeNull()
    expect(device.created_at).toBeGreaterThan(0)

    const found = repo.findById('mac-1')
    expect(found).toEqual(device)
  })

  it('finds device by token', () => {
    const repo = createDeviceRepository(db)
    repo.create({ id: 'mac-1', name: 'My Mac', role: 'mac' })
    repo.updateToken('mac-1', 'test-token')

    const found = repo.findByToken('test-token')
    expect(found?.id).toBe('mac-1')
    expect(found?.token).toBe('test-token')
  })

  it('returns undefined for non-existent device', () => {
    const repo = createDeviceRepository(db)
    expect(repo.findById('nope')).toBeUndefined()
    expect(repo.findByToken('nope')).toBeUndefined()
  })

  it('deletes a device', () => {
    const repo = createDeviceRepository(db)
    repo.create({ id: 'mac-1', name: 'My Mac', role: 'mac' })

    expect(repo.delete('mac-1')).toBe(true)
    expect(repo.findById('mac-1')).toBeUndefined()
    expect(repo.delete('mac-1')).toBe(false)
  })

  it('updates last seen', () => {
    const repo = createDeviceRepository(db)
    repo.create({ id: 'mac-1', name: 'My Mac', role: 'mac' })

    repo.updateLastSeen('mac-1')
    const device = repo.findById('mac-1')
    expect(device?.last_seen_at).toBeGreaterThan(0)
  })
})

describe('PairRepository', () => {
  it('creates and finds a pair', () => {
    const devices = createDeviceRepository(db)
    const pairs = createPairRepository(db)

    devices.create({ id: 'mac-1', name: 'My Mac', role: 'mac' })

    const pair = pairs.create({
      id: 'pair-1',
      mac_device_id: 'mac-1',
      pair_code: 'ABC123',
      expires_at: Math.floor(Date.now() / 1000) + 300,
    })

    expect(pair.id).toBe('pair-1')
    expect(pair.status).toBe('pending')
    expect(pair.attempts).toBe(0)

    const found = pairs.findByCode('ABC123')
    expect(found?.id).toBe('pair-1')
  })

  it('completes a pair', () => {
    const devices = createDeviceRepository(db)
    const pairs = createPairRepository(db)

    devices.create({ id: 'mac-1', name: 'My Mac', role: 'mac' })
    devices.create({ id: 'phone-1', name: 'My Phone', role: 'phone' })

    pairs.create({
      id: 'pair-1',
      mac_device_id: 'mac-1',
      pair_code: 'ABC123',
      expires_at: Math.floor(Date.now() / 1000) + 300,
    })

    pairs.complete('pair-1', 'phone-1')

    const pair = pairs.findById('pair-1')
    expect(pair?.status).toBe('completed')
    expect(pair?.phone_device_id).toBe('phone-1')
  })

  it('checks if devices are paired', () => {
    const devices = createDeviceRepository(db)
    const pairs = createPairRepository(db)

    devices.create({ id: 'mac-1', name: 'My Mac', role: 'mac' })
    devices.create({ id: 'phone-1', name: 'My Phone', role: 'phone' })

    expect(pairs.isPaired('mac-1', 'phone-1')).toBe(false)

    pairs.create({
      id: 'pair-1',
      mac_device_id: 'mac-1',
      pair_code: 'ABC123',
      expires_at: Math.floor(Date.now() / 1000) + 300,
    })
    pairs.complete('pair-1', 'phone-1')

    expect(pairs.isPaired('mac-1', 'phone-1')).toBe(true)
  })

  it('increments attempts', () => {
    const devices = createDeviceRepository(db)
    const pairs = createPairRepository(db)

    devices.create({ id: 'mac-1', name: 'My Mac', role: 'mac' })

    pairs.create({
      id: 'pair-1',
      mac_device_id: 'mac-1',
      pair_code: 'ABC123',
      expires_at: Math.floor(Date.now() / 1000) + 300,
    })

    pairs.incrementAttempts('pair-1')
    pairs.incrementAttempts('pair-1')

    const pair = pairs.findById('pair-1')
    expect(pair?.attempts).toBe(2)
  })

  it('expires a pair', () => {
    const devices = createDeviceRepository(db)
    const pairs = createPairRepository(db)

    devices.create({ id: 'mac-1', name: 'My Mac', role: 'mac' })

    pairs.create({
      id: 'pair-1',
      mac_device_id: 'mac-1',
      pair_code: 'ABC123',
      expires_at: Math.floor(Date.now() / 1000) + 300,
    })

    pairs.expire('pair-1')

    // findByCode only returns pending pairs
    expect(pairs.findByCode('ABC123')).toBeUndefined()
    expect(pairs.findById('pair-1')?.status).toBe('expired')
  })

  it('finds active pairs by mac', () => {
    const devices = createDeviceRepository(db)
    const pairs = createPairRepository(db)

    devices.create({ id: 'mac-1', name: 'My Mac', role: 'mac' })
    devices.create({ id: 'phone-1', name: 'Phone 1', role: 'phone' })
    devices.create({ id: 'phone-2', name: 'Phone 2', role: 'phone' })

    pairs.create({
      id: 'pair-1',
      mac_device_id: 'mac-1',
      pair_code: 'AAA111',
      expires_at: Math.floor(Date.now() / 1000) + 300,
    })
    pairs.complete('pair-1', 'phone-1')

    pairs.create({
      id: 'pair-2',
      mac_device_id: 'mac-1',
      pair_code: 'BBB222',
      expires_at: Math.floor(Date.now() / 1000) + 300,
    })
    pairs.complete('pair-2', 'phone-2')

    const active = pairs.findActivePairsByMac('mac-1')
    expect(active).toHaveLength(2)
  })
})
