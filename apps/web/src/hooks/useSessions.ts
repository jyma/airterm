import { useReducer, useCallback } from 'react'
import type { SessionInfo, TerminalEvent, SequencedMessage } from '@airterm/protocol'

export interface SessionState {
  readonly sessions: readonly SessionInfo[]
  readonly events: Record<string, readonly TerminalEvent[]>
}

type SessionAction =
  | { type: 'SET_SESSIONS'; sessions: readonly SessionInfo[] }
  | { type: 'APPEND_EVENTS'; sessionId: string; events: readonly TerminalEvent[] }
  | { type: 'CLEAR_EVENTS'; sessionId: string }

function reducer(state: SessionState, action: SessionAction): SessionState {
  switch (action.type) {
    case 'SET_SESSIONS':
      return { ...state, sessions: action.sessions }
    case 'APPEND_EVENTS':
      return {
        ...state,
        events: {
          ...state.events,
          [action.sessionId]: [...(state.events[action.sessionId] ?? []), ...action.events],
        },
      }
    case 'CLEAR_EVENTS':
      return {
        ...state,
        events: {
          ...state.events,
          [action.sessionId]: [],
        },
      }
  }
}

const INITIAL_STATE: SessionState = { sessions: [], events: {} }

export function useSessions() {
  const [state, dispatch] = useReducer(reducer, INITIAL_STATE)

  const handleMessage = useCallback((sequenced: SequencedMessage) => {
    const msg = sequenced.message
    switch (msg.kind) {
      case 'sessions':
        dispatch({ type: 'SET_SESSIONS', sessions: msg.sessions })
        break
      case 'output':
        dispatch({
          type: 'APPEND_EVENTS',
          sessionId: msg.sessionId,
          events: msg.events,
        })
        break
    }
  }, [])

  return { ...state, handleMessage }
}
