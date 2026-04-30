import { describe, it, expect, beforeEach } from 'vitest'
import {
  HandshakeState,
  generateNoiseKeyPair,
  type CipherState,
  type HandshakeResult,
} from '@airterm/crypto'
import {
  type SignalingMessage,
  type TakeoverFrame,
} from '@airterm/protocol'
import { TakeoverChannel, TakeoverChannelError } from '../takeover-channel'

/// Sets up a complete IK round trip and returns both sides' transport
/// CipherStates so each test can wire two channels back-to-back and
/// verify wire round trips.
function makePair(): { initFinal: HandshakeResult; respFinal: HandshakeResult } {
  const macStatic = generateNoiseKeyPair()
  const phoneStatic = generateNoiseKeyPair()
  const initiator = new HandshakeState({
    initiator: true,
    prologue: new Uint8Array(0),
    s: phoneStatic,
    rs: macStatic.publicKey,
  })
  const responder = new HandshakeState({
    initiator: false,
    prologue: new Uint8Array(0),
    s: macStatic,
  })
  const messageA = initiator.writeMessageA(new Uint8Array(0))
  responder.readMessageA(messageA)
  const messageB = responder.writeMessageB(new Uint8Array(0))
  initiator.readMessageB(messageB)
  return {
    initFinal: initiator.finalize(),
    respFinal: responder.finalize(),
  }
}

interface Wired {
  initiatorChannel: TakeoverChannel
  responderChannel: TakeoverChannel
  initiatorInbox: TakeoverFrame[]
  responderInbox: TakeoverFrame[]
  initiatorErrors: TakeoverChannelError[]
  responderErrors: TakeoverChannelError[]
  /// Manually deliver the next message between channels — lets tests
  /// inspect / tamper / drop / replay frames mid-stream.
  deliver: () => void
  pending: { from: 'initiator' | 'responder'; msg: SignalingMessage }[]
}

function wirePair(): Wired {
  const { initFinal, respFinal } = makePair()
  const initiatorErrors: TakeoverChannelError[] = []
  const responderErrors: TakeoverChannelError[] = []
  const initiatorInbox: TakeoverFrame[] = []
  const responderInbox: TakeoverFrame[] = []
  const pending: { from: 'initiator' | 'responder'; msg: SignalingMessage }[] = []

  const initiatorChannel = new TakeoverChannel({
    send: initFinal.send,
    receive: initFinal.receive,
    sendSignaling: (msg) => pending.push({ from: 'initiator', msg }),
    onFrame: (frame) => initiatorInbox.push(frame),
    onError: (e) => initiatorErrors.push(e),
  })
  const responderChannel = new TakeoverChannel({
    send: respFinal.send,
    receive: respFinal.receive,
    sendSignaling: (msg) => pending.push({ from: 'responder', msg }),
    onFrame: (frame) => responderInbox.push(frame),
    onError: (e) => responderErrors.push(e),
  })

  return {
    initiatorChannel,
    responderChannel,
    initiatorInbox,
    responderInbox,
    initiatorErrors,
    responderErrors,
    pending,
    deliver: () => {
      const next = pending.shift()
      if (!next) return
      if (next.from === 'initiator') {
        responderChannel.handleIncoming(next.msg)
      } else {
        initiatorChannel.handleIncoming(next.msg)
      }
    },
  }
}

describe('TakeoverChannel', () => {
  let wired: Wired
  beforeEach(() => {
    wired = wirePair()
  })

  it('round-trips a screen_snapshot frame from initiator to responder', () => {
    const frame: TakeoverFrame = {
      kind: 'screen_snapshot',
      seq: 1,
      rows: 1,
      cols: 1,
      cells: [[{ ch: 'X' }]],
      cursor: { row: 0, col: 0, visible: true },
    }
    wired.initiatorChannel.sendFrame(frame)
    wired.deliver()
    expect(wired.responderInbox).toHaveLength(1)
    expect(wired.responderInbox[0]).toEqual(frame)
  })

  it('round-trips an input_event frame from responder to initiator', () => {
    const frame: TakeoverFrame = {
      kind: 'input_event',
      seq: 0,
      bytes: btoa('ls\r'),
    }
    wired.responderChannel.sendFrame(frame)
    wired.deliver()
    expect(wired.initiatorInbox).toHaveLength(1)
    expect(wired.initiatorInbox[0]).toEqual(frame)
  })

  it('keeps both directions independent under interleaved traffic', () => {
    const f1: TakeoverFrame = {
      kind: 'screen_delta',
      seq: 1,
      rows: [{ row: 0, cells: [{ ch: 'a' }] }],
    }
    const f2: TakeoverFrame = {
      kind: 'input_event',
      seq: 0,
      bytes: btoa('A'),
    }
    const f3: TakeoverFrame = {
      kind: 'screen_delta',
      seq: 2,
      rows: [{ row: 0, cells: [{ ch: 'b' }] }],
    }

    wired.initiatorChannel.sendFrame(f1)
    wired.responderChannel.sendFrame(f2)
    wired.initiatorChannel.sendFrame(f3)
    while (wired.pending.length > 0) wired.deliver()

    expect(wired.responderInbox).toEqual([f1, f3])
    expect(wired.initiatorInbox).toEqual([f2])
  })

  it('drops a replayed encrypted frame and reports it via onError', () => {
    const frame: TakeoverFrame = {
      kind: 'screen_snapshot',
      seq: 1,
      rows: 1,
      cols: 1,
      cells: [[{ ch: 'A' }]],
      cursor: { row: 0, col: 0, visible: true },
    }
    wired.initiatorChannel.sendFrame(frame)
    const captured = wired.pending[0].msg
    wired.deliver()
    expect(wired.responderInbox).toHaveLength(1)

    // Re-deliver the same envelope — should be flagged as replay.
    wired.responderChannel.handleIncoming(captured)
    expect(wired.responderInbox).toHaveLength(1)
    expect(wired.responderErrors.map((e) => e.code)).toContain('replay')
  })

  it('reports AEAD failure when ciphertext is tampered', () => {
    wired.initiatorChannel.sendFrame({
      kind: 'ping',
      seq: 0,
      ts: 100,
    })
    const next = wired.pending[0].msg
    expect(next.kind).toBe('encrypted')
    if (next.kind !== 'encrypted') return
    const tampered = {
      ...next,
      // Flip a base64 char so the ciphertext bytes shift slightly.
      ciphertext: next.ciphertext.replace(/[A-Z]/, 'a'),
    }
    wired.responderChannel.handleIncoming(tampered)
    expect(wired.responderErrors.map((e) => e.code)).toContain('aead_failure')
    expect(wired.responderInbox).toHaveLength(0)
  })

  it('ignores non-encrypted SignalingMessages (handshake frames stay with caller)', () => {
    const handed = wired.responderChannel.handleIncoming({
      kind: 'noise',
      stage: 1,
      noisePayload: 'AAAA',
    })
    expect(handed).toBe(false)
    expect(wired.responderInbox).toHaveLength(0)
    expect(wired.responderErrors).toHaveLength(0)
  })

  it('refuses to send after close', () => {
    wired.initiatorChannel.close()
    expect(() =>
      wired.initiatorChannel.sendFrame({
        kind: 'ping',
        seq: 0,
        ts: 1,
      })
    ).toThrow(/closed/)
  })
})
