/**
 * Sequence number manager for anti-replay protection.
 * Each direction (Mac→Phone, Phone→Mac) has independent sequence numbers.
 */

export interface SequenceState {
  /** Next outgoing sequence number */
  readonly nextSeq: number
  /** Last acknowledged incoming sequence number */
  readonly lastAck: number
  /** Expected incoming sequence number */
  readonly expectedSeq: number
}

export function createSequenceState(): SequenceState {
  return { nextSeq: 1, lastAck: 0, expectedSeq: 1 }
}

/**
 * Allocate the next outgoing sequence number.
 * Returns the new state and the allocated seq.
 */
export function allocateSeq(state: SequenceState): { state: SequenceState; seq: number } {
  return {
    state: { ...state, nextSeq: state.nextSeq + 1 },
    seq: state.nextSeq,
  }
}

/**
 * Update ack value (latest seq we've received from the other side).
 */
export function updateAck(state: SequenceState, receivedSeq: number): SequenceState {
  return {
    ...state,
    lastAck: Math.max(state.lastAck, receivedSeq),
  }
}

/**
 * Validate an incoming sequence number.
 * Returns 'ok' | 'duplicate' | 'out_of_order'.
 */
export function validateSeq(
  state: SequenceState,
  incomingSeq: number,
): { result: 'ok' | 'duplicate' | 'out_of_order'; state: SequenceState } {
  if (incomingSeq < state.expectedSeq) {
    return { result: 'duplicate', state }
  }

  if (incomingSeq > state.expectedSeq) {
    return { result: 'out_of_order', state }
  }

  return {
    result: 'ok',
    state: { ...state, expectedSeq: state.expectedSeq + 1 },
  }
}

/**
 * Build AAD (Additional Authenticated Data) from seq + ack.
 * This binds the sequence numbers to the ciphertext, preventing replay.
 */
export function buildAAD(seq: number, ack: number): Uint8Array {
  const buffer = new ArrayBuffer(8)
  const view = new DataView(buffer)
  view.setUint32(0, seq, false)
  view.setUint32(4, ack, false)
  return new Uint8Array(buffer)
}
