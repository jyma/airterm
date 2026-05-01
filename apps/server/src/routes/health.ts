import { Hono } from 'hono'
import type { DeviceRepository } from '../db/devices.js'
import type { PairRepository } from '../db/pairs.js'
import type { WSManager } from '../ws/manager.js'

export interface HealthRouteDeps {
  readonly devices: DeviceRepository
  readonly pairs: PairRepository
  readonly wsManager: WSManager
}

const PROCESS_START_MS = Date.now()

/// Three endpoints:
///
///   GET /health           — minimal liveness probe (Fly TCP check + Docker
///                           HEALTHCHECK consume this; keep payload small).
///   GET /health/detailed  — JSON with operational counts; behind a
///                           bearer token if `HEALTH_TOKEN` is set so the
///                           paired-device count isn't a public stat.
///   GET /metrics          — Prometheus text exposition. Same token gate
///                           as /health/detailed.
export function createHealthRoutes(deps?: HealthRouteDeps): Hono {
  const app = new Hono()
  const guardToken = process.env.HEALTH_TOKEN ?? null

  app.get('/health', (c) => {
    return c.json({
      status: 'ok',
      timestamp: Date.now(),
      version: '0.1.0',
    })
  })

  // The detailed + metrics endpoints need the dependency bundle. When
  // tests construct the route without it (legacy /health behaviour),
  // we just don't register them.
  if (!deps) return app

  app.get('/health/detailed', (c) => {
    if (!authorised(c.req.header('authorization'), guardToken)) {
      return c.json({ error: 'Unauthorized' }, 401)
    }
    return c.json(buildDetailed(deps))
  })

  app.get('/metrics', (c) => {
    if (!authorised(c.req.header('authorization'), guardToken)) {
      return c.text('Unauthorized\n', 401)
    }
    c.header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
    return c.text(buildPrometheus(deps))
  })

  return app
}

interface DetailedHealth {
  readonly status: 'ok'
  readonly timestamp: number
  readonly version: string
  readonly uptimeMs: number
  readonly connections: { mac: number; phone: number; total: number }
  readonly devices: { mac: number; phone: number }
  readonly pairs: { pending: number; completed: number; expired: number }
}

function buildDetailed(deps: HealthRouteDeps): DetailedHealth {
  const conns = deps.wsManager.getConnectionsByRole()
  const devicesByRole = deps.devices.countByRole()
  const pairsByStatus = deps.pairs.countByStatus()
  return {
    status: 'ok',
    timestamp: Date.now(),
    version: '0.1.0',
    uptimeMs: Date.now() - PROCESS_START_MS,
    connections: { ...conns, total: conns.mac + conns.phone },
    devices: devicesByRole,
    pairs: pairsByStatus,
  }
}

/// Minimal Prometheus text exposition. Each line:
///   # HELP <metric> <doc>
///   # TYPE <metric> <gauge|counter>
///   <metric>{...labels} <value>
///
/// Hand-rolled instead of pulling in `prom-client` so the runtime
/// image stays small and we don't drag a 100 kB dep for six gauges.
function buildPrometheus(deps: HealthRouteDeps): string {
  const conns = deps.wsManager.getConnectionsByRole()
  const dev = deps.devices.countByRole()
  const pairs = deps.pairs.countByStatus()
  const lines: string[] = []

  function emit(
    metric: string,
    help: string,
    samples: Array<{ labels?: Record<string, string>; value: number }>
  ): void {
    lines.push(`# HELP ${metric} ${help}`)
    lines.push(`# TYPE ${metric} gauge`)
    for (const s of samples) {
      const lbl = s.labels
        ? '{' + Object.entries(s.labels).map(([k, v]) => `${k}="${v}"`).join(',') + '}'
        : ''
      lines.push(`${metric}${lbl} ${s.value}`)
    }
  }

  emit('airterm_ws_connections', 'Open WebSocket connections to the relay.', [
    { labels: { role: 'mac' }, value: conns.mac },
    { labels: { role: 'phone' }, value: conns.phone },
  ])
  emit('airterm_devices_total', 'Devices registered in the relay database.', [
    { labels: { role: 'mac' }, value: dev.mac },
    { labels: { role: 'phone' }, value: dev.phone },
  ])
  emit('airterm_pairs_total', 'Pair records by status.', [
    { labels: { status: 'pending' }, value: pairs.pending },
    { labels: { status: 'completed' }, value: pairs.completed },
    { labels: { status: 'expired' }, value: pairs.expired },
  ])
  emit('airterm_uptime_seconds', 'Seconds since the relay process started.', [
    { value: Math.floor((Date.now() - PROCESS_START_MS) / 1000) },
  ])

  return lines.join('\n') + '\n'
}

/// Bearer-token gate. When `HEALTH_TOKEN` isn't set in the environment
/// the endpoints are open — useful for local development. In production
/// the maintainer sets a long random secret and points their scraper at
/// `Authorization: Bearer <token>`.
function authorised(header: string | undefined, token: string | null): boolean {
  if (!token) return true
  if (!header) return false
  const match = header.match(/^Bearer\s+(.+)$/i)
  return match?.[1] === token
}
