/**
 * Mock Mac Client — simulates a Mac pushing session data to the relay server.
 *
 * Usage: npx tsx scripts/mock-mac.ts
 *
 * Flow:
 *  1. Init pairing → get pairCode + macToken
 *  2. Display pairCode for user to enter on Web UI
 *  3. Connect WebSocket as "mac"
 *  4. Wait for pair_completed notification
 *  5. Push mock session + terminal events to the paired phone
 */

const SERVER = process.env.SERVER_URL ?? 'http://8.218.78.18'
const WS_SERVER = SERVER.replace(/^http/, 'ws')
const MAC_ID = `mock-mac-${Date.now()}`
const MAC_NAME = 'My MacBook Pro'

interface PairInitResponse {
  pairId: string
  pairCode: string
  expiresAt: number
  token: string
}

async function main() {
  console.log('╔══════════════════════════════════╗')
  console.log('║     AirTerm Mock Mac Client      ║')
  console.log('╚══════════════════════════════════╝\n')

  // 1. Init pairing
  const initRes = await fetch(`${SERVER}/api/pair/init`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ macDeviceId: MAC_ID, macName: MAC_NAME }),
  })
  const { pairCode, token: macToken } = (await initRes.json()) as PairInitResponse

  console.log(`  Pair Code:  \x1b[1;36m${pairCode}\x1b[0m`)
  console.log(`  Web UI:     http://localhost:5173/pair`)
  console.log(`  Enter the pair code on the Web UI.\n`)

  // 2. Connect WebSocket
  const ws = new WebSocket(`${WS_SERVER}/ws/mac?token=${macToken}`)
  let phoneDeviceId: string | null = null

  ws.onopen = () => {
    console.log('  ✓ WebSocket connected to relay server')
    console.log('  Waiting for phone to pair...\n')
  }

  ws.onerror = (e) => {
    console.error('  ✗ WebSocket error:', e)
  }

  ws.onclose = (e) => {
    console.log(`  WebSocket closed (code: ${e.code})`)
  }

  ws.onmessage = (event) => {
    try {
      const data = JSON.parse(event.data as string)

      if (data.type === 'pair_completed') {
        phoneDeviceId = data.phoneDeviceId
        console.log(`  ✓ Phone paired: ${data.phoneName} (${data.phoneDeviceId.slice(0, 8)}...)`)
        console.log('  Starting mock session data push...\n')
        startMockSession(ws, phoneDeviceId!)
        return
      }

      if (data.type === 'relay' && data.payload) {
        const decoded = JSON.parse(atob(data.payload))
        console.log(`  ← Phone:`, JSON.stringify(decoded.message))

        // Handle phone input
        if (decoded.message?.kind === 'input') {
          console.log(`  ← Input: "${decoded.message.text}"`)
          sendSessionOutput(
            ws,
            phoneDeviceId!,
            `Received: ${decoded.message.text}`,
          )
        } else if (decoded.message?.kind === 'approval') {
          const action = decoded.message.action
          console.log(`  ← Approval: ${action}`)
          sendSessionOutput(
            ws,
            phoneDeviceId!,
            action === 'allow' ? '✓ Command approved, executing...' : '✗ Command denied',
          )
        } else if (decoded.message?.kind === 'shortcut') {
          console.log(`  ← Shortcut: ${decoded.message.command}`)
          sendSessionOutput(
            ws,
            phoneDeviceId!,
            `Running shortcut: ${decoded.message.command}`,
          )
        }
      }
    } catch {
      // ignore
    }
  }
}

let seq = 0

function sendRelay(ws: WebSocket, targetId: string, message: Record<string, unknown>) {
  seq++
  const payload = Buffer.from(JSON.stringify({ seq, ack: 0, message })).toString('base64')
  ws.send(
    JSON.stringify({
      type: 'relay',
      from: MAC_ID,
      to: targetId,
      ts: Date.now(),
      payload,
    }),
  )
}

function sendSessionOutput(ws: WebSocket, targetId: string, text: string) {
  sendRelay(ws, targetId, {
    kind: 'output',
    sessionId: 'sess_mock_001',
    events: [{ type: 'message', text }],
  })
}

function startMockSession(ws: WebSocket, targetId: string) {
  // Send session list
  sendRelay(ws, targetId, {
    kind: 'sessions',
    sessions: [
      {
        id: 'sess_mock_001',
        name: 'auth refactor',
        cwd: '~/projects/myapp',
        terminal: 'AirTerm',
        status: 'active',
        lastOutput: 'Analyzing auth.ts...',
        needsApproval: false,
      },
    ],
  })
  console.log('  → Sent session list')

  // Simulate terminal output sequence
  const events = [
    { delay: 2000, text: '╭─ Claude\n│ I\'ll analyze the auth module and fix the security issues.\n│ Let me start by reading the current implementation.' },
    { delay: 4000, text: '► Read src/auth.ts (245 lines)' },
    { delay: 6000, text: '╭─ Claude\n│ Found 3 security issues:\n│ 1. Hardcoded JWT secret\n│ 2. No token expiration\n│ 3. Missing input validation' },
    { delay: 8000, diff: true },
    { delay: 10000, approval: true },
    { delay: 15000, text: '╭─ Claude\n│ All 3 issues have been fixed. Running tests...' },
    { delay: 17000, text: '► Bash: npm test\n\n  PASS  src/auth.test.ts\n  ✓ validates JWT secret from env (3ms)\n  ✓ rejects expired tokens (2ms)\n  ✓ validates input schema (1ms)\n\n  Tests: 3 passed' },
    { delay: 19000, completion: true },
  ]

  for (const event of events) {
    setTimeout(() => {
      if (event.diff) {
        sendRelay(ws, targetId, {
          kind: 'output',
          sessionId: 'sess_mock_001',
          events: [
            {
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
            },
          ],
        })
        console.log('  → Sent diff event')
      } else if (event.approval) {
        // Update session to needsApproval
        sendRelay(ws, targetId, {
          kind: 'sessions',
          sessions: [
            {
              id: 'sess_mock_001',
              name: 'auth refactor',
              cwd: '~/projects/myapp',
              terminal: 'AirTerm',
              status: 'active',
              lastOutput: 'Waiting for approval...',
              needsApproval: true,
            },
          ],
        })
        sendRelay(ws, targetId, {
          kind: 'output',
          sessionId: 'sess_mock_001',
          events: [
            {
              type: 'approval',
              tool: 'Bash',
              command: 'npm test',
              prompt: 'Allow Bash: npm test?',
            },
          ],
        })
        console.log('  → Sent approval request (waiting for phone response)')
      } else if (event.completion) {
        sendRelay(ws, targetId, {
          kind: 'output',
          sessionId: 'sess_mock_001',
          events: [{ type: 'completion', summary: 'Auth module security fixes complete — 3 issues resolved' }],
        })
        sendRelay(ws, targetId, {
          kind: 'sessions',
          sessions: [
            {
              id: 'sess_mock_001',
              name: 'auth refactor',
              cwd: '~/projects/myapp',
              terminal: 'AirTerm',
              status: 'ended',
              lastOutput: 'Auth fixes complete',
              needsApproval: false,
            },
          ],
        })
        console.log('  → Session completed ✓')
      } else {
        sendSessionOutput(ws, targetId, event.text!)
        console.log(`  → Sent output event`)
      }
    }, event.delay)
  }
}

main().catch(console.error)
