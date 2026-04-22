import { describe, it, expect } from 'vitest'
import type {
  SessionInfo,
  SessionsMessage,
  OutputMessage,
  InputMessage,
  ApprovalMessage,
  ShortcutMessage,
  BlockedMessage,
  PingMessage,
  PongMessage,
  MessageEvent,
  DiffEvent,
  ApprovalEvent,
  ToolCallEvent,
  CompletionEvent,
} from '../messages.js'

describe('Protocol Messages', () => {
  it('creates a valid SessionInfo', () => {
    const session: SessionInfo = {
      id: 'session-1',
      name: 'auth 重构',
      cwd: '~/projects/myapp',
      terminal: 'iTerm2',
      status: 'active',
      lastOutput: '正在执行 Bash...',
      needsApproval: false,
    }
    expect(session.id).toBe('session-1')
    expect(session.status).toBe('active')
    expect(session.needsApproval).toBe(false)
  })

  it('creates a valid SessionsMessage', () => {
    const msg: SessionsMessage = {
      kind: 'sessions',
      sessions: [
        {
          id: 's1',
          name: 'test',
          cwd: '/home',
          terminal: 'Terminal',
          status: 'active',
          lastOutput: '',
          needsApproval: false,
        },
      ],
    }
    expect(msg.kind).toBe('sessions')
    expect(msg.sessions).toHaveLength(1)
  })

  it('creates valid terminal events', () => {
    const msgEvent: MessageEvent = {
      type: 'message',
      text: 'Hello from Claude',
    }
    expect(msgEvent.type).toBe('message')

    const diffEvent: DiffEvent = {
      type: 'diff',
      file: 'src/auth.ts',
      hunks: [
        {
          oldStart: 42,
          lines: [
            { op: 'remove', text: 'const token = "hardcoded"' },
            { op: 'add', text: 'const token = process.env.AUTH_TOKEN' },
          ],
        },
      ],
    }
    expect(diffEvent.hunks[0].lines).toHaveLength(2)

    const approvalEvent: ApprovalEvent = {
      type: 'approval',
      tool: 'Bash',
      command: 'npm test',
      prompt: 'Allow running npm test?',
    }
    expect(approvalEvent.tool).toBe('Bash')

    const toolCallEvent: ToolCallEvent = {
      type: 'tool_call',
      tool: 'Read',
      args: { file: 'src/auth.ts' },
      output: 'file content here',
    }
    expect(toolCallEvent.tool).toBe('Read')

    const completionEvent: CompletionEvent = {
      type: 'completion',
      summary: 'Task completed successfully',
    }
    expect(completionEvent.summary).toBeTruthy()
  })

  it('creates valid input and control messages', () => {
    const input: InputMessage = {
      kind: 'input',
      sessionId: 's1',
      text: 'hello claude',
    }
    expect(input.kind).toBe('input')

    const approval: ApprovalMessage = {
      kind: 'approval',
      sessionId: 's1',
      action: 'allow',
    }
    expect(approval.action).toBe('allow')

    const shortcut: ShortcutMessage = {
      kind: 'shortcut',
      sessionId: 's1',
      command: '/commit',
    }
    expect(shortcut.command).toBe('/commit')

    const blocked: BlockedMessage = {
      kind: 'blocked',
      sessionId: 's1',
      reason: 'Dangerous command blocked',
      original: 'rm -rf /',
      requiresMacConfirm: true,
    }
    expect(blocked.reason).toBeTruthy()

    const ping: PingMessage = { kind: 'ping' }
    const pong: PongMessage = { kind: 'pong' }
    expect(ping.kind).toBe('ping')
    expect(pong.kind).toBe('pong')
  })

  it('creates a valid output message with events', () => {
    const output: OutputMessage = {
      kind: 'output',
      sessionId: 's1',
      events: [
        { type: 'message', text: 'Analyzing code...' },
        {
          type: 'diff',
          file: 'test.ts',
          hunks: [{ oldStart: 1, lines: [{ op: 'add', text: 'new line' }] }],
        },
      ],
    }
    expect(output.events).toHaveLength(2)
    expect(output.events[0].type).toBe('message')
    expect(output.events[1].type).toBe('diff')
  })
})
