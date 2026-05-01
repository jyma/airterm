import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  ATTR_BOLD,
  ATTR_DIM,
  ATTR_ITALIC,
  ATTR_REVERSE,
  ATTR_STRIKETHROUGH,
  ATTR_UNDERLINE,
  type CellFrame,
  type CursorFrame,
  type ScreenDeltaFrame,
  type ScreenSnapshotFrame,
  type TakeoverFrame,
} from '@airterm/protocol'
import type { TakeoverChannel } from '../lib/takeover-channel'
import { bytesToBase64, keyToBytes } from '../lib/key-mapper'

/// Phone-side terminal mirror. Subscribes to inbound TakeoverFrames
/// from a live `TakeoverChannel` and renders the cell grid as a stack
/// of monospace rows. Pure React state — no xterm.js, no canvas. The
/// Mac side already parsed ANSI escape sequences into typed cells, so
/// we don't need a second VT state machine on the phone.
///
/// Phase 4 MVP: render-only. Keyboard input wires up next slice.

interface TakeoverViewerProps {
  readonly channel: TakeoverChannel
  /// Optional fallback grid dimensions while waiting for the first
  /// snapshot — keeps the layout from collapsing during the
  /// 0–33 ms before the Mac's first frame lands.
  readonly initialRows?: number
  readonly initialCols?: number
}

interface ViewState {
  rows: number
  cols: number
  cells: CellFrame[][]
  cursor: CursorFrame
  title: string
  framesReceived: number
}

const EMPTY_CELL: CellFrame = { ch: ' ' }

function emptyState(rows: number, cols: number): ViewState {
  return {
    rows,
    cols,
    cells: Array.from({ length: rows }, () =>
      Array.from({ length: cols }, () => EMPTY_CELL)
    ),
    cursor: { row: 0, col: 0, visible: false },
    title: '',
    framesReceived: 0,
  }
}

/// Apply one inbound frame to the prior state, returning a fresh
/// `ViewState`. We always allocate fresh row arrays (immutable update)
/// so React can use referential equality cheaply for memoization
/// further down the tree.
function reduce(prev: ViewState, frame: TakeoverFrame): ViewState {
  switch (frame.kind) {
    case 'screen_snapshot': {
      const snap = frame as ScreenSnapshotFrame
      return {
        rows: snap.rows,
        cols: snap.cols,
        cells: snap.cells.map((r) => [...r]),
        cursor: snap.cursor,
        title: snap.title ?? prev.title,
        framesReceived: prev.framesReceived + 1,
      }
    }
    case 'screen_delta': {
      const delta = frame as ScreenDeltaFrame
      const cells = prev.cells.map((r) => r)
      for (const change of delta.rows) {
        if (change.row >= 0 && change.row < cells.length) {
          cells[change.row] = [...change.cells]
        }
      }
      return {
        rows: prev.rows,
        cols: prev.cols,
        cells,
        cursor: delta.cursor ?? prev.cursor,
        title: delta.title ?? prev.title,
        framesReceived: prev.framesReceived + 1,
      }
    }
    case 'bye':
      return prev
    default:
      return prev
  }
}

export function TakeoverViewer({
  channel,
  initialRows = 24,
  initialCols = 80,
}: TakeoverViewerProps) {
  const [state, setState] = useState<ViewState>(() =>
    emptyState(initialRows, initialCols)
  )
  const [keysSent, setKeysSent] = useState(0)
  const containerRef = useRef<HTMLDivElement>(null)
  const inputSeqRef = useRef(0)

  useEffect(() => {
    channel.onFrame = (frame) => {
      setState((prev) => reduce(prev, frame))
    }
    channel.onError = () => {
      // Surface in a future status pill; for now, log.
      // eslint-disable-next-line no-console
      console.warn('takeover channel error')
    }
    return () => {
      channel.onFrame = () => {}
      channel.onError = () => {}
    }
  }, [channel])

  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLDivElement>) => {
      const bytes = keyToBytes(event.nativeEvent)
      if (!bytes) return
      // Block the browser default ONLY when we recognised the key —
      // otherwise the user can't shift-tab out of the viewer.
      event.preventDefault()
      try {
        channel.sendFrame({
          kind: 'input_event',
          seq: inputSeqRef.current++,
          bytes: bytesToBase64(bytes),
        })
        setKeysSent((n) => n + 1)
      } catch {
        // Channel closed — silently ignore; the parent route will
        // navigate away when WS dies.
      }
    },
    [channel]
  )

  // Auto-focus on mount so users can start typing immediately on
  // desktop. On phones, the visible keyboard pops up only after the
  // user taps the surface anyway, so this is a no-op there.
  useEffect(() => {
    containerRef.current?.focus()
  }, [])

  return (
    <section style={containerStyle}>
      {state.title && <header style={titleStyle}>{state.title}</header>}
      <div
        ref={containerRef}
        tabIndex={0}
        onKeyDown={handleKeyDown}
        style={focusableStyle}
      >
        <Grid state={state} />
      </div>
      <footer style={footerStyle}>
        {state.framesReceived === 0
          ? 'Waiting for Mac to start broadcasting…'
          : `${state.cols}×${state.rows} · ${state.framesReceived} frames in · ${keysSent} keys out`}
      </footer>
    </section>
  )
}

const focusableStyle: React.CSSProperties = {
  outline: 'none',
}

interface GridProps {
  readonly state: ViewState
}

function Grid({ state }: GridProps) {
  // Memoise per-row rendering so a single-row delta only re-renders
  // that row, not the entire grid.
  const rows = useMemo(
    () =>
      state.cells.map((row, rIdx) => (
        <Row
          key={rIdx}
          cells={row}
          isCursorRow={rIdx === state.cursor.row && state.cursor.visible}
          cursorCol={
            rIdx === state.cursor.row && state.cursor.visible
              ? state.cursor.col
              : -1
          }
        />
      )),
    [state.cells, state.cursor]
  )
  return <div style={gridStyle}>{rows}</div>
}

interface RowProps {
  readonly cells: CellFrame[]
  readonly isCursorRow: boolean
  readonly cursorCol: number
}

function Row({ cells, cursorCol }: RowProps) {
  return (
    <div style={rowStyle}>
      {cells.map((cell, cIdx) => (
        <CellSpan key={cIdx} cell={cell} isCursor={cIdx === cursorCol} />
      ))}
    </div>
  )
}

interface CellSpanProps {
  readonly cell: CellFrame
  readonly isCursor: boolean
}

function CellSpan({ cell, isCursor }: CellSpanProps) {
  const attrs = cell.attrs ?? 0
  const reverse = (attrs & ATTR_REVERSE) !== 0
  const fgRGB = cell.fg ?? null
  const bgRGB = cell.bg ?? null
  const finalFg = reverse ? bgRGB ?? null : fgRGB
  const finalBg = reverse ? fgRGB ?? null : bgRGB

  const style: React.CSSProperties = {
    color: finalFg !== null ? rgbCss(finalFg) : 'inherit',
    background: isCursor
      ? 'var(--color-accent-blue)'
      : finalBg !== null
        ? rgbCss(finalBg)
        : 'transparent',
    fontWeight: (attrs & ATTR_BOLD) !== 0 ? 600 : 400,
    fontStyle: (attrs & ATTR_ITALIC) !== 0 ? 'italic' : 'normal',
    textDecorationLine: textDecorationFor(attrs),
    opacity: (attrs & ATTR_DIM) !== 0 ? 0.6 : 1,
    width: cell.width === 2 ? '2ch' : '1ch',
    display: 'inline-block',
    whiteSpace: 'pre',
  }
  // Render an explicit space for empty content so layout is stable.
  return <span style={style}>{cell.ch === '' ? ' ' : cell.ch}</span>
}

function textDecorationFor(attrs: number): string {
  const parts: string[] = []
  if ((attrs & ATTR_UNDERLINE) !== 0) parts.push('underline')
  if ((attrs & ATTR_STRIKETHROUGH) !== 0) parts.push('line-through')
  return parts.length === 0 ? 'none' : parts.join(' ')
}

function rgbCss(packed: number): string {
  const r = (packed >> 16) & 0xff
  const g = (packed >> 8) & 0xff
  const b = packed & 0xff
  return `rgb(${r}, ${g}, ${b})`
}

// ---- styles ----

const containerStyle: React.CSSProperties = {
  display: 'flex',
  flexDirection: 'column',
  gap: 8,
  background: 'var(--color-bg-overlay)',
  borderRadius: 'var(--radius-card)',
  padding: 12,
  fontFamily: 'var(--font-mono)',
}

const titleStyle: React.CSSProperties = {
  fontSize: 12,
  color: 'var(--color-text-secondary)',
  fontWeight: 500,
}

const gridStyle: React.CSSProperties = {
  display: 'flex',
  flexDirection: 'column',
  fontSize: 13,
  lineHeight: 1.2,
  letterSpacing: 0,
  overflow: 'auto',
  whiteSpace: 'pre',
  // Force a sane minimum so the cursor is visible on small phones.
  minHeight: 240,
}

const rowStyle: React.CSSProperties = {
  display: 'flex',
  whiteSpace: 'pre',
}

const footerStyle: React.CSSProperties = {
  fontSize: 11,
  color: 'var(--color-text-muted)',
  fontFamily: 'var(--font-ui)',
}
