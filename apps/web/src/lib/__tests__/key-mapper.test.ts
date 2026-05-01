import { describe, it, expect } from 'vitest'
import { bytesToBase64, keyToBytes } from '../key-mapper'

function fakeEvent(opts: Partial<KeyboardEvent>): KeyboardEvent {
  return {
    key: '',
    ctrlKey: false,
    altKey: false,
    shiftKey: false,
    metaKey: false,
    ...opts,
  } as KeyboardEvent
}

function decode(bytes: Uint8Array | null): string {
  return bytes ? new TextDecoder().decode(bytes) : ''
}

describe('keyToBytes — printable characters', () => {
  it('passes through ASCII letters', () => {
    expect(decode(keyToBytes(fakeEvent({ key: 'a' })))).toBe('a')
    expect(decode(keyToBytes(fakeEvent({ key: 'Z' })))).toBe('Z')
  })

  it('passes through punctuation', () => {
    expect(decode(keyToBytes(fakeEvent({ key: ';' })))).toBe(';')
    expect(decode(keyToBytes(fakeEvent({ key: '/' })))).toBe('/')
  })

  it('UTF-8 encodes multi-byte chars', () => {
    const bytes = keyToBytes(fakeEvent({ key: '中' }))
    expect(bytes).not.toBeNull()
    // U+4E2D in UTF-8: e4 b8 ad
    expect(Array.from(bytes!)).toEqual([0xe4, 0xb8, 0xad])
  })
})

describe('keyToBytes — control sequences', () => {
  it('Enter → CR', () => {
    expect(decode(keyToBytes(fakeEvent({ key: 'Enter' })))).toBe('\r')
  })
  it('Backspace → DEL (0x7f)', () => {
    expect(Array.from(keyToBytes(fakeEvent({ key: 'Backspace' }))!)).toEqual([0x7f])
  })
  it('Tab → HT (0x09)', () => {
    expect(Array.from(keyToBytes(fakeEvent({ key: 'Tab' }))!)).toEqual([0x09])
  })
  it('Escape → ESC (0x1b)', () => {
    expect(Array.from(keyToBytes(fakeEvent({ key: 'Escape' }))!)).toEqual([0x1b])
  })

  it.each([
    ['ArrowUp',    'A'],
    ['ArrowDown',  'B'],
    ['ArrowRight', 'C'],
    ['ArrowLeft',  'D'],
    ['Home',       'H'],
    ['End',        'F'],
  ])('%s → CSI %s', (key, csiSuffix) => {
    expect(decode(keyToBytes(fakeEvent({ key })))).toBe(`\x1b[${csiSuffix}`)
  })

  it('PageUp / PageDown / Delete → CSI ~', () => {
    expect(decode(keyToBytes(fakeEvent({ key: 'PageUp' })))).toBe('\x1b[5~')
    expect(decode(keyToBytes(fakeEvent({ key: 'PageDown' })))).toBe('\x1b[6~')
    expect(decode(keyToBytes(fakeEvent({ key: 'Delete' })))).toBe('\x1b[3~')
  })
})

describe('keyToBytes — modifier keys', () => {
  it('Ctrl+letter → C0 control byte', () => {
    expect(Array.from(keyToBytes(fakeEvent({ key: 'a', ctrlKey: true }))!)).toEqual([0x01])
    expect(Array.from(keyToBytes(fakeEvent({ key: 'C', ctrlKey: true }))!)).toEqual([0x03])
  })

  it('Alt+letter → ESC prefix', () => {
    expect(decode(keyToBytes(fakeEvent({ key: 'b', altKey: true })))).toBe('\x1bb')
  })

  it('bare modifier press returns null', () => {
    expect(keyToBytes(fakeEvent({ key: 'Shift' }))).toBeNull()
    expect(keyToBytes(fakeEvent({ key: 'Control' }))).toBeNull()
    expect(keyToBytes(fakeEvent({ key: 'Alt' }))).toBeNull()
    expect(keyToBytes(fakeEvent({ key: 'Meta' }))).toBeNull()
  })

  it('unknown special keys return null', () => {
    expect(keyToBytes(fakeEvent({ key: 'F19' }))).toBeNull()
    expect(keyToBytes(fakeEvent({ key: 'CapsLock' }))).toBeNull()
  })
})

describe('bytesToBase64', () => {
  it('round-trips through atob', () => {
    const bytes = new TextEncoder().encode('ls -la\r')
    expect(atob(bytesToBase64(bytes))).toBe('ls -la\r')
  })
})
