import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import WebSocket from 'ws'
import {
  HandshakeState,
  generateNoiseKeyPair,
} from '@airterm/crypto'
import { startTestServer, type TestServer } from './helpers/test-server.js'

/// End-to-end Noise IK pair flow against the real relay.
///
/// Spins up a real Hono + WebSocket server in-process, simulates the
/// Mac responder and the phone initiator with `@airterm/crypto`'s
/// HandshakeState, and walks the entire handshake through the WS
/// relay layer. Verifies:
///
///   • the relay forwards `relay`-typed envelopes between paired
///     devices unchanged (the server never inspects the payload),
///   • Mac learns the phone's static public key from message A,
///   • Phone reads the responder's message B and finalises with the
///     same handshake hash the Mac computed,
///   • bidirectional transport encryption works after split.
///
/// This is the single test that catches drift across all four moving
/// parts at once: protocol schema, crypto primitives, server WS
/// router, and the message-wrapping convention each side uses.

let server: TestServer

beforeEach(async () => {
  server = await startTestServer()
})

afterEach(async () => {
  await server.close()
})

describe('Noise IK pair E2E (server + simulated Mac + simulated Phone)', () => {
  it('completes a Noise IK handshake over the live relay', async () => {
    const macStaticKeyPair = generateNoiseKeyPair()
    const phoneStaticKeyPair = generateNoiseKeyPair()

    // ---- Mac side: pair-init + open WS ----

    const initRes = await fetch(`${server.url}/api/pair/init`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ macDeviceId: 'mac-e2e', macName: 'Mac E2E' }),
    })
    expect(initRes.status).toBe(200)
    const initBody = (await initRes.json()) as {
      pairCode: string
      token: string
    }
    expect(initBody.pairCode).toHaveLength(6)

    const macWs = new WebSocket(
      `${server.wsUrl}/ws/mac?token=${initBody.token}`
    )
    await waitForOpen(macWs)
    const macInbox: unknown[] = []
    macWs.on('message', (raw) => {
      try {
        macInbox.push(JSON.parse(String(raw)))
      } catch {
        // ignore non-JSON pings
      }
    })

    // ---- Phone side: pair-complete + open WS ----

    const completeRes = await fetch(`${server.url}/api/pair/complete`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pairCode: initBody.pairCode,
        phoneDeviceId: 'phone-e2e',
        phoneName: 'Phone E2E',
      }),
    })
    expect(completeRes.status).toBe(200)
    const completeBody = (await completeRes.json()) as {
      token: string
      macDeviceId: string
    }
    expect(completeBody.macDeviceId).toBe('mac-e2e')

    // Mac should observe the server's pair_completed push.
    await waitFor(() =>
      macInbox.some(
        (m) => isObject(m) && (m as { type?: string }).type === 'pair_completed'
      )
    )

    const phoneWs = new WebSocket(
      `${server.wsUrl}/ws/phone?token=${completeBody.token}`
    )
    await waitForOpen(phoneWs)
    const phoneInbox: unknown[] = []
    phoneWs.on('message', (raw) => {
      try {
        phoneInbox.push(JSON.parse(String(raw)))
      } catch {
        // ignore
      }
    })

    // ---- Phone: write Noise IK message A, send through relay ----

    const phoneHs = new HandshakeState({
      initiator: true,
      prologue: new Uint8Array(0),
      s: phoneStaticKeyPair,
      rs: macStaticKeyPair.publicKey,
    })
    const messageA = phoneHs.writeMessageA(new Uint8Array(0))
    sendRelay(phoneWs, 'phone-e2e', completeBody.macDeviceId, {
      kind: 'noise',
      stage: 1,
      noisePayload: bufToB64(messageA),
    })

    // ---- Mac: receive A, run handshake, send B ----

    const macHs = new HandshakeState({
      initiator: false,
      prologue: new Uint8Array(0),
      s: macStaticKeyPair,
    })

    const stage1Inbound = await waitForRelayMessage(macInbox, 'noise', 1)
    const messageABytes = b64ToBuf(stage1Inbound.noisePayload as string)
    const recoveredA = macHs.readMessageA(messageABytes)
    expect(recoveredA.length).toBe(0)
    expect(macHs.rs).not.toBeNull()
    expect(Array.from(macHs.rs!)).toEqual(Array.from(phoneStaticKeyPair.publicKey))

    const messageB = macHs.writeMessageB(new Uint8Array(0))
    sendRelay(macWs, 'mac-e2e', 'phone-e2e', {
      kind: 'noise',
      stage: 2,
      noisePayload: bufToB64(messageB),
    })

    // ---- Phone: receive B, finalise ----

    const stage2Inbound = await waitForRelayMessage(phoneInbox, 'noise', 2)
    const messageBBytes = b64ToBuf(stage2Inbound.noisePayload as string)
    const recoveredB = phoneHs.readMessageB(messageBBytes)
    expect(recoveredB.length).toBe(0)

    const phoneFinal = phoneHs.finalize()
    const macFinal = macHs.finalize()

    // Channel-binding hashes must match byte-for-byte.
    expect(Array.from(phoneFinal.handshakeHash)).toEqual(
      Array.from(macFinal.handshakeHash)
    )

    // ---- Bidirectional transport encryption smoke test ----

    const ping = phoneFinal.send.encrypt(new TextEncoder().encode('ping-1'))
    const pingRecovered = macFinal.receive.decrypt(ping)
    expect(new TextDecoder().decode(pingRecovered)).toBe('ping-1')

    const pong = macFinal.send.encrypt(new TextEncoder().encode('pong-1'))
    const pongRecovered = phoneFinal.receive.decrypt(pong)
    expect(new TextDecoder().decode(pongRecovered)).toBe('pong-1')

    macWs.close()
    phoneWs.close()
  })

  it('rejects relay traffic before pair_completed binds the (mac, phone) tuple', async () => {
    // Two devices that never paired with each other shouldn't be able to
    // relay — the WS manager checks `pairs.isPaired(macId, phoneId)`
    // before forwarding. Sanity-check that the gate actually fires.
    //
    // Mac initiates, gets a token + ws, phone shows up at the WS layer
    // without ever calling /api/pair/complete.
    const initRes = await fetch(`${server.url}/api/pair/init`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ macDeviceId: 'mac-x', macName: 'Mac X' }),
    })
    const { token: macToken } = (await initRes.json()) as {
      token: string
      pairCode: string
    }

    const macWs = new WebSocket(`${server.wsUrl}/ws/mac?token=${macToken}`)
    await waitForOpen(macWs)
    const macInbox: unknown[] = []
    macWs.on('message', (raw) => {
      try { macInbox.push(JSON.parse(String(raw))) } catch { /* skip */ }
    })

    // Phone tries to talk to mac without ever pair-completing — server
    // should respond on the SENDER socket with an error, and crucially
    // not deliver to the mac. We can't open a phone WS at all without a
    // token, so we test the converse: mac trying to relay to a phone
    // that doesn't exist gets the not-paired error.
    sendRelay(macWs, 'mac-x', 'phone-imaginary', {
      kind: 'noise',
      stage: 1,
      noisePayload: 'AAAA',
    })
    await new Promise((r) => setTimeout(r, 100))
    const errorEcho = macInbox.find(
      (m) =>
        isObject(m) &&
        typeof (m as { error?: string }).error === 'string'
    )
    expect(errorEcho).toBeTruthy()
    macWs.close()
  })
})

// MARK: - helpers

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null
}

function waitForOpen(ws: WebSocket): Promise<void> {
  return new Promise((resolve, reject) => {
    ws.once('open', () => resolve())
    ws.once('error', reject)
  })
}

let outboundSeq = 0
function sendRelay(
  ws: WebSocket,
  from: string,
  to: string,
  message: Record<string, unknown>
): void {
  outboundSeq += 1
  const sequenced = { seq: outboundSeq, ack: 0, message }
  const payload = btoa(JSON.stringify(sequenced))
  const envelope = { type: 'relay', from, to, ts: Date.now(), payload }
  ws.send(JSON.stringify(envelope))
}

async function waitForRelayMessage(
  inbox: unknown[],
  kind: string,
  stage: number,
  timeoutMs = 3000
): Promise<Record<string, unknown>> {
  const start = Date.now()
  while (Date.now() - start < timeoutMs) {
    for (const m of inbox) {
      if (!isObject(m)) continue
      if ((m as { type?: string }).type !== 'relay') continue
      const payload = (m as { payload?: string }).payload
      if (typeof payload !== 'string') continue
      try {
        const seq = JSON.parse(atob(payload)) as {
          message?: { kind?: string; stage?: number }
        }
        const msg = seq.message
        if (
          msg &&
          msg.kind === kind &&
          msg.stage === stage
        ) {
          return msg as Record<string, unknown>
        }
      } catch {
        // ignore malformed envelopes
      }
    }
    await new Promise((r) => setTimeout(r, 10))
  }
  throw new Error(`waitForRelayMessage(${kind}, ${stage}) timed out after ${timeoutMs}ms`)
}

async function waitFor(
  predicate: () => boolean,
  timeoutMs = 3000
): Promise<void> {
  const start = Date.now()
  while (!predicate()) {
    if (Date.now() - start > timeoutMs) {
      throw new Error('waitFor() timed out')
    }
    await new Promise((r) => setTimeout(r, 10))
  }
}

function bufToB64(b: Uint8Array): string {
  let s = ''
  for (const c of b) s += String.fromCharCode(c)
  return btoa(s)
}

function b64ToBuf(s: string): Uint8Array {
  const bin = atob(s)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}
