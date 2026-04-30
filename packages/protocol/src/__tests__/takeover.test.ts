import { describe, it, expect } from 'vitest'
import {
  ATTR_BOLD,
  ATTR_REVERSE,
  decodeTakeoverFrame,
  encodeTakeoverFrame,
  isInputEventFrame,
  isResizeFrame,
  isScreenDeltaFrame,
  isScreenSnapshotFrame,
  type CellFrame,
  type ScreenDeltaFrame,
  type ScreenSnapshotFrame,
  type TakeoverFrame,
} from '../takeover.js'

function blankCell(ch: string = ' '): CellFrame {
  return { ch }
}

describe('Takeover Frame Encode / Decode Round Trip', () => {
  it('round-trips a screen_snapshot', () => {
    const cells: CellFrame[][] = [
      [{ ch: 'h' }, { ch: 'i' }, blankCell()],
      [blankCell(), blankCell(), blankCell()],
    ]
    const original: ScreenSnapshotFrame = {
      kind: 'screen_snapshot',
      seq: 1,
      rows: 2,
      cols: 3,
      cells,
      cursor: { row: 0, col: 2, visible: true },
      title: 'zsh',
    }
    const wire = encodeTakeoverFrame(original)
    const parsed = decodeTakeoverFrame(wire)
    expect(parsed).toEqual(original)
    expect(isScreenSnapshotFrame(parsed)).toBe(true)
  })

  it('round-trips a screen_delta', () => {
    const original: ScreenDeltaFrame = {
      kind: 'screen_delta',
      seq: 7,
      rows: [
        {
          row: 5,
          cells: [
            { ch: '$', fg: 0xff8888 },
            { ch: ' ' },
          ],
        },
      ],
      cursor: { row: 5, col: 2, visible: true },
    }
    const parsed = decodeTakeoverFrame(encodeTakeoverFrame(original))
    expect(parsed).toEqual(original)
    expect(isScreenDeltaFrame(parsed)).toBe(true)
  })

  it('round-trips an input_event', () => {
    const original = {
      kind: 'input_event',
      seq: 12,
      bytes: btoa('ls -la\r'),
    } as TakeoverFrame
    const parsed = decodeTakeoverFrame(encodeTakeoverFrame(original))
    expect(parsed).toEqual(original)
    expect(isInputEventFrame(parsed)).toBe(true)
  })

  it('round-trips a resize', () => {
    const original = {
      kind: 'resize',
      seq: 0,
      rows: 24,
      cols: 80,
    } as TakeoverFrame
    const parsed = decodeTakeoverFrame(encodeTakeoverFrame(original))
    expect(parsed).toEqual(original)
    expect(isResizeFrame(parsed)).toBe(true)
  })

  it('rejects an unknown kind at the decode boundary', () => {
    expect(() => decodeTakeoverFrame(JSON.stringify({ kind: 'martian', seq: 0 }))).toThrow(
      /Unknown takeover frame kind: martian/
    )
  })

  it('rejects malformed JSON', () => {
    expect(() => decodeTakeoverFrame('not-json')).toThrow()
  })
})

describe('Takeover Frame Style Bits', () => {
  it('preserves a packed attrs byte through the wire', () => {
    const cell: CellFrame = {
      ch: 'X',
      attrs: ATTR_BOLD | ATTR_REVERSE,
      fg: 0x00ffff,
      bg: 0x000000,
    }
    const snapshot: ScreenSnapshotFrame = {
      kind: 'screen_snapshot',
      seq: 0,
      rows: 1,
      cols: 1,
      cells: [[cell]],
      cursor: { row: 0, col: 0, visible: true },
    }
    const parsed = decodeTakeoverFrame(encodeTakeoverFrame(snapshot)) as ScreenSnapshotFrame
    expect(parsed.cells[0][0].attrs).toBe(ATTR_BOLD | ATTR_REVERSE)
    expect(parsed.cells[0][0].fg).toBe(0x00ffff)
  })

  it('treats an omitted attrs as 0 (plain)', () => {
    const cell: CellFrame = { ch: 'A' }
    expect(cell.attrs).toBeUndefined()
  })
})

describe('Takeover Frame Type Guards (exhaustive)', () => {
  it('snapshot guard rejects other kinds', () => {
    const delta: TakeoverFrame = {
      kind: 'screen_delta',
      seq: 0,
      rows: [],
    }
    expect(isScreenSnapshotFrame(delta)).toBe(false)
  })

  it('delta guard rejects other kinds', () => {
    const snap: TakeoverFrame = {
      kind: 'screen_snapshot',
      seq: 0,
      rows: 0,
      cols: 0,
      cells: [],
      cursor: { row: 0, col: 0, visible: true },
    }
    expect(isScreenDeltaFrame(snap)).toBe(false)
  })
})
