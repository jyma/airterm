/**
 * Mock Mac Client — simulates a Mac pushing session data to the relay server.
 *
 * Usage: npx tsx scripts/mock-mac.ts
 */

const SERVER = process.env.SERVER_URL ?? 'http://localhost:3000'
const WS_SERVER = SERVER.replace(/^http/, 'ws')
const MAC_ID = `mock-mac-${Date.now()}`
const MAC_NAME = 'My MacBook Pro'

interface PairInitResponse {
  pairId: string
  pairCode: string
  expiresAt: number
  token: string
}

// Current session state
let currentSession = {
  id: 'sess_mock_001',
  name: 'auth 重构',
  cwd: '~/projects/myapp',
  terminal: 'AirTerm',
  status: 'active',
  lastOutput: '正在分析...',
  needsApproval: false,
}

let allEvents: Record<string, unknown>[] = []
let phoneDeviceId: string | null = null
let ws: WebSocket

async function main() {
  console.log('╔══════════════════════════════════╗')
  console.log('║     AirTerm Mock Mac Client      ║')
  console.log('╚══════════════════════════════════╝\n')

  const initRes = await fetch(`${SERVER}/api/pair/init`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ macDeviceId: MAC_ID, macName: MAC_NAME }),
  })
  const { pairCode, token: macToken } = (await initRes.json()) as PairInitResponse

  console.log(`  Pair Code:  \x1b[1;36m${pairCode}\x1b[0m`)
  console.log(`  Web UI:     http://localhost:5173/pair?code=${pairCode}`)
  console.log(`  Enter the pair code on the Web UI.\n`)

  ws = new WebSocket(`${WS_SERVER}/ws/mac?token=${macToken}`)

  ws.onopen = () => {
    console.log('  ✓ WebSocket connected to relay server')
    console.log('  Waiting for phone to pair...\n')
  }

  ws.onerror = (e) => console.error('  ✗ WebSocket error:', e)
  ws.onclose = (e) => console.log(`  WebSocket closed (code: ${e.code})`)

  ws.onmessage = (event) => {
    try {
      const data = JSON.parse(event.data as string)

      if (data.type === 'pair_completed') {
        phoneDeviceId = data.phoneDeviceId
        console.log(`  ✓ Phone paired: ${data.phoneName} (${data.phoneDeviceId.slice(0, 8)}...)`)
        console.log('  Starting mock session...\n')
        pushFullState()
        startMockSession()
        return
      }

      if (data.type === 'relay' && data.payload) {
        const decoded = JSON.parse(atob(data.payload))
        const msg = decoded.message ?? decoded
        handlePhoneMessage(msg)
      }
    } catch {
      // ignore
    }
  }
}

let seq = 0

function sendRelay(targetId: string, message: Record<string, unknown>) {
  seq++
  const payload = Buffer.from(JSON.stringify({ seq, ack: 0, message })).toString('base64')
  ws.send(JSON.stringify({ type: 'relay', from: MAC_ID, to: targetId, ts: Date.now(), payload }))
}

function pushFullState() {
  if (!phoneDeviceId) return
  // Push session list
  sendRelay(phoneDeviceId, { kind: 'sessions', sessions: [currentSession] })
  console.log('  → Pushed session list')

  // Push accumulated events
  if (allEvents.length > 0) {
    sendRelay(phoneDeviceId, { kind: 'output', sessionId: currentSession.id, events: allEvents })
    console.log(`  → Pushed ${allEvents.length} cached events`)
  }
}

function pushEvent(event: Record<string, unknown>) {
  allEvents.push(event)
  if (!phoneDeviceId) return
  sendRelay(phoneDeviceId, { kind: 'output', sessionId: currentSession.id, events: [event] })
}

function pushSessionUpdate(updates: Partial<typeof currentSession>) {
  currentSession = { ...currentSession, ...updates }
  if (!phoneDeviceId) return
  sendRelay(phoneDeviceId, { kind: 'sessions', sessions: [currentSession] })
}

function handlePhoneMessage(msg: Record<string, unknown>) {
  if (!phoneDeviceId) return

  switch (msg.kind) {
    case 'input': {
      const text = msg.text as string
      console.log(`  ← Input: "${text}"`)
      pushEvent({ type: 'message', text: `收到指令: ${text}` })
      break
    }
    case 'approval': {
      const action = msg.action as string
      console.log(`  ← Approval: ${action}`)
      if (action === 'allow') {
        pushSessionUpdate({ needsApproval: false, lastOutput: '正在执行...' })
        pushEvent({ type: 'message', text: '✓ 命令已批准，正在执行...' })
        // Simulate command execution
        setTimeout(() => {
          pushEvent({
            type: 'tool_call',
            tool: 'Bash',
            args: { command: 'npm test' },
            output: 'PASS src/auth.test.ts\nTests: 3 passed, 3 total',
          })
          pushEvent({ type: 'completion', summary: '所有测试通过，auth 重构完成' })
          pushSessionUpdate({ status: 'ended', lastOutput: 'auth 重构完成' })
        }, 2000)
      } else {
        pushSessionUpdate({ needsApproval: false, lastOutput: '命令已拒绝' })
        pushEvent({ type: 'message', text: '✗ 命令已被拒绝' })
      }
      break
    }
    case 'shortcut': {
      const command = msg.command as string
      console.log(`  ← Shortcut: ${command}`)
      pushEvent({ type: 'message', text: `执行快捷指令: ${command}` })
      break
    }
  }
}

function startMockSession() {
  const events: { delay: number; action: () => void }[] = [
    {
      delay: 1000,
      action: () => {
        pushEvent({ type: 'message', text: '我来分析 auth.ts 中的安全问题。\n让我先读取当前实现。' })
      },
    },
    {
      delay: 3000,
      action: () => {
        pushEvent({ type: 'tool_call', tool: 'Read', args: { file: 'src/auth.ts' }, output: '245 lines' })
      },
    },
    {
      delay: 5000,
      action: () => {
        pushEvent({
          type: 'message',
          text: '发现 3 个安全问题：\n1. 硬编码 JWT secret\n2. Token 无过期时间\n3. 缺少输入校验',
        })
      },
    },
    {
      delay: 7000,
      action: () => {
        pushEvent({
          type: 'diff',
          file: 'src/auth.ts',
          hunks: [
            {
              oldStart: 5,
              lines: [
                { op: 'remove', text: 'const JWT_SECRET = "hardcoded-secret"' },
                { op: 'add', text: 'const JWT_SECRET = process.env.JWT_SECRET' },
                { op: 'add', text: 'if (!JWT_SECRET) throw new Error("JWT_SECRET required")' },
              ],
            },
            {
              oldStart: 23,
              lines: [
                { op: 'remove', text: 'const token = jwt.sign(payload, JWT_SECRET)' },
                { op: 'add', text: 'const token = jwt.sign(payload, JWT_SECRET, { expiresIn: "15m" })' },
              ],
            },
          ],
        })
        pushEvent({ type: 'message', text: '已修复硬编码 token。现在运行测试确认。' })
      },
    },
    {
      delay: 10000,
      action: () => {
        pushSessionUpdate({ needsApproval: true, lastOutput: '等待确认: npm test' })
        pushEvent({ type: 'approval', tool: 'Bash', command: 'npm test', prompt: 'Allow Bash: npm test?' })
        console.log('  → Sent approval request (waiting for phone response...)')
      },
    },
  ]

  for (const { delay, action } of events) {
    setTimeout(action, delay)
  }
}

main().catch(console.error)

// Keep process alive
setInterval(() => {}, 60_000)
