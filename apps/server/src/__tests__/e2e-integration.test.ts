import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { startTestServer, type TestServer } from './helpers/test-server.js'
import {
  createMockDevice,
  pairDevices,
  decodeRelayPayload,
} from './helpers/mock-device.js'

let server: TestServer

beforeAll(async () => {
  server = await startTestServer()
})

afterAll(async () => {
  await server.close()
})

describe('E2E Integration: Pairing + Relay', { sequential: true }, () => {
  it('TC-1: Mac receives pair_completed notification after phone completes pairing', async () => {
    const macId = `mac-tc1-${Date.now()}`

    // Mac initiates pairing
    const initRes = await fetch(`${server.url}/api/pair/init`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ macDeviceId: macId, macName: 'TC1 Mac' }),
    })
    const { pairCode, token: macToken } = await initRes.json()

    // Mac connects WS and waits for notification
    const mac = createMockDevice(macId, macToken, 'mac')
    await mac.connect(server.wsUrl)

    // Phone completes pairing
    const phoneId = `phone-tc1-${Date.now()}`
    const completeRes = await fetch(`${server.url}/api/pair/complete`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pairCode,
        phoneDeviceId: phoneId,
        phoneName: 'TC1 Phone',
      }),
    })
    expect(completeRes.status).toBe(200)

    // Mac should receive pair_completed notification
    const notification = (await mac.waitForMessage(
      (msg: any) => msg.type === 'pair_completed',
    )) as any

    expect(notification.type).toBe('pair_completed')
    expect(notification.phoneDeviceId).toBe(phoneId)
    expect(notification.phoneName).toBe('TC1 Phone')

    await mac.close()
  })

  it('TC-2: Mac→Phone relay (sessions message)', async () => {
    const { macId, phoneId, macToken, phoneToken } = await pairDevices(server.url)

    const mac = createMockDevice(macId, macToken, 'mac')
    const phone = createMockDevice(phoneId, phoneToken, 'phone')
    await mac.connect(server.wsUrl)
    await phone.connect(server.wsUrl)

    // Mac sends sessions list
    mac.sendRelay(phoneId, {
      kind: 'sessions',
      sessions: [
        {
          id: 'sess-1',
          name: 'test session',
          cwd: '/tmp',
          terminal: 'AirTerm',
          status: 'active',
          lastOutput: 'hello',
          needsApproval: false,
        },
      ],
    })

    // Phone should receive the relay envelope
    const envelope = (await phone.waitForMessage(
      (msg: any) => msg.type === 'relay',
    )) as any

    expect(envelope.type).toBe('relay')
    expect(envelope.from).toBe(macId)

    const decoded = decodeRelayPayload(envelope)
    expect(decoded).not.toBeNull()
    expect(decoded!.message.kind).toBe('sessions')
    expect((decoded!.message as any).sessions).toHaveLength(1)
    expect((decoded!.message as any).sessions[0].name).toBe('test session')

    await mac.close()
    await phone.close()
  })

  it('TC-3: Mac→Phone relay (output events)', async () => {
    const { macId, phoneId, macToken, phoneToken } = await pairDevices(server.url)

    const mac = createMockDevice(macId, macToken, 'mac')
    const phone = createMockDevice(phoneId, phoneToken, 'phone')
    await mac.connect(server.wsUrl)
    await phone.connect(server.wsUrl)

    mac.sendRelay(phoneId, {
      kind: 'output',
      sessionId: 'sess-1',
      events: [
        { type: 'message', text: 'Hello from Mac terminal' },
        { type: 'tool_call', tool: 'Read', args: { file: 'src/index.ts' }, output: '42 lines' },
      ],
    })

    const envelope = (await phone.waitForMessage(
      (msg: any) => msg.type === 'relay',
    )) as any

    const decoded = decodeRelayPayload(envelope)
    expect(decoded!.message.kind).toBe('output')
    expect((decoded!.message as any).events).toHaveLength(2)
    expect((decoded!.message as any).events[0].text).toBe('Hello from Mac terminal')
    expect((decoded!.message as any).events[1].tool).toBe('Read')

    await mac.close()
    await phone.close()
  })

  it('TC-4: Phone→Mac relay (input message)', async () => {
    const { macId, phoneId, macToken, phoneToken } = await pairDevices(server.url)

    const mac = createMockDevice(macId, macToken, 'mac')
    const phone = createMockDevice(phoneId, phoneToken, 'phone')
    await mac.connect(server.wsUrl)
    await phone.connect(server.wsUrl)

    phone.sendRelay(macId, {
      kind: 'input',
      sessionId: 'sess-1',
      text: 'ls -la',
    })

    const envelope = (await mac.waitForMessage(
      (msg: any) => msg.type === 'relay',
    )) as any

    const decoded = decodeRelayPayload(envelope)
    expect(decoded!.message.kind).toBe('input')
    expect((decoded!.message as any).text).toBe('ls -la')

    await mac.close()
    await phone.close()
  })

  it('TC-5: Bidirectional approval flow', async () => {
    const { macId, phoneId, macToken, phoneToken } = await pairDevices(server.url)

    const mac = createMockDevice(macId, macToken, 'mac')
    const phone = createMockDevice(phoneId, phoneToken, 'phone')
    await mac.connect(server.wsUrl)
    await phone.connect(server.wsUrl)

    // Mac sends approval request
    mac.sendRelay(phoneId, {
      kind: 'output',
      sessionId: 'sess-1',
      events: [
        { type: 'approval', tool: 'Bash', command: 'rm -rf /tmp/test', prompt: 'Allow?' },
      ],
    })

    const approvalEnvelope = (await phone.waitForMessage(
      (msg: any) => msg.type === 'relay',
    )) as any
    const approvalDecoded = decodeRelayPayload(approvalEnvelope)
    expect((approvalDecoded!.message as any).events[0].type).toBe('approval')
    expect((approvalDecoded!.message as any).events[0].command).toBe('rm -rf /tmp/test')

    // Phone sends approval response
    phone.sendRelay(macId, {
      kind: 'approval',
      sessionId: 'sess-1',
      action: 'allow',
    })

    const responseEnvelope = (await mac.waitForMessage(
      (msg: any) => msg.type === 'relay',
    )) as any
    const responseDecoded = decodeRelayPayload(responseEnvelope)
    expect(responseDecoded!.message.kind).toBe('approval')
    expect((responseDecoded!.message as any).action).toBe('allow')

    await mac.close()
    await phone.close()
  })

  it('TC-6: Unpaired devices are rejected', async () => {
    // Create two independent pairs
    const pairA = await pairDevices(server.url)
    const pairB = await pairDevices(server.url)

    const phoneA = createMockDevice(pairA.phoneId, pairA.phoneToken, 'phone')
    const macB = createMockDevice(pairB.macId, pairB.macToken, 'mac')
    await phoneA.connect(server.wsUrl)
    await macB.connect(server.wsUrl)

    // Phone-A tries to send to Mac-B (not paired)
    phoneA.sendRelay(pairB.macId, {
      kind: 'input',
      sessionId: 'sess-1',
      text: 'unauthorized',
    })

    const error = (await phoneA.waitForMessage(
      (msg: any) => msg.error != null,
    )) as any

    expect(error.code).toBe(4002)
    expect(error.error).toContain('Not paired')

    await phoneA.close()
    await macB.close()
  })

  it('TC-7: Target device offline returns error', async () => {
    const { macId, phoneId, phoneToken } = await pairDevices(server.url)

    // Only phone connects, mac stays offline
    const phone = createMockDevice(phoneId, phoneToken, 'phone')
    await phone.connect(server.wsUrl)

    phone.sendRelay(macId, {
      kind: 'input',
      sessionId: 'sess-1',
      text: 'hello',
    })

    const error = (await phone.waitForMessage(
      (msg: any) => msg.error != null,
    )) as any

    expect(error.code).toBe(4004)
    expect(error.error).toContain('offline')

    await phone.close()
  })

  it('TC-8: Reconnected device receives messages', async () => {
    const { macId, phoneId, macToken, phoneToken } = await pairDevices(server.url)

    const mac = createMockDevice(macId, macToken, 'mac')
    await mac.connect(server.wsUrl)

    // Phone connects then disconnects
    const phone1 = createMockDevice(phoneId, phoneToken, 'phone')
    await phone1.connect(server.wsUrl)
    await phone1.close()

    // Phone reconnects with new instance (same token)
    const phone2 = createMockDevice(phoneId, phoneToken, 'phone')
    await phone2.connect(server.wsUrl)

    // Mac sends message to reconnected phone
    mac.sendRelay(phoneId, {
      kind: 'output',
      sessionId: 'sess-1',
      events: [{ type: 'message', text: 'after reconnect' }],
    })

    const envelope = (await phone2.waitForMessage(
      (msg: any) => msg.type === 'relay',
    )) as any

    const decoded = decodeRelayPayload(envelope)
    expect((decoded!.message as any).events[0].text).toBe('after reconnect')

    await mac.close()
    await phone2.close()
  })
}, 30000)
