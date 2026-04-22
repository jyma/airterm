/**
 * Structured logger for AirTerm relay server.
 * Outputs JSON lines for production, human-readable for development.
 */

const isDev = process.env.NODE_ENV !== 'production'

interface LogEntry {
  readonly level: 'info' | 'warn' | 'error'
  readonly msg: string
  readonly ts: string
  readonly [key: string]: unknown
}

function formatEntry(entry: LogEntry): string {
  if (isDev) {
    const { level, msg, ts, ...rest } = entry
    const extras = Object.keys(rest).length > 0 ? ` ${JSON.stringify(rest)}` : ''
    return `[${ts}] ${level.toUpperCase()} ${msg}${extras}`
  }
  return JSON.stringify(entry)
}

function log(level: 'info' | 'warn' | 'error', msg: string, data?: Record<string, unknown>): void {
  const entry: LogEntry = {
    level,
    msg,
    ts: new Date().toISOString(),
    ...data,
  }
  const output = formatEntry(entry)
  if (level === 'error') {
    process.stderr.write(output + '\n')
  } else {
    process.stdout.write(output + '\n')
  }
}

export const logger = {
  info: (msg: string, data?: Record<string, unknown>) => log('info', msg, data),
  warn: (msg: string, data?: Record<string, unknown>) => log('warn', msg, data),
  error: (msg: string, data?: Record<string, unknown>) => log('error', msg, data),
}
