import 'dotenv/config'
import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { serve } from '@hono/node-server'
import { WebSocketServer } from 'ws'
import type { IncomingMessage } from 'node:http'
import { loadConfig } from './config.js'
import { createDatabase } from './db/init.js'
import { createDeviceRepository } from './db/devices.js'
import { createPairRepository } from './db/pairs.js'
import { createTokenService } from './auth/token.js'
import { createWSManager } from './ws/manager.js'
import { createHealthRoutes } from './routes/health.js'
import { createPairRoutes } from './routes/pair.js'
import { createAuthRoutes } from './routes/auth.js'
import { createRateLimiter } from './utils/rate-limit.js'
import { createJWTService } from './auth/jwt.js'

const config = loadConfig()
const db = createDatabase(config.dbPath)
const devices = createDeviceRepository(db)
const pairs = createPairRepository(db)
const tokenService = createTokenService(config.jwtSecret)
const wsManager = createWSManager({ tokenService, devices, pairs })
const jwtService = createJWTService(config.jwtSecret)

// Rate limiters
const pairRateLimiter = createRateLimiter(10, 60_000) // 10 requests per minute per IP
const globalRateLimiter = createRateLimiter(100, 60_000) // 100 requests per minute per IP

const app = new Hono()

app.use('*', cors())

// Global rate limiting
app.use('*', async (c, next) => {
  const ip = c.req.header('x-forwarded-for') ?? c.req.header('x-real-ip') ?? 'unknown'
  if (!globalRateLimiter.check(ip)) {
    return c.json({ error: 'Too many requests' }, 429)
  }
  await next()
})

// Stricter rate limit for pairing endpoints
app.use('/api/pair/*', async (c, next) => {
  const ip = c.req.header('x-forwarded-for') ?? c.req.header('x-real-ip') ?? 'unknown'
  if (!pairRateLimiter.check(ip)) {
    return c.json({ error: 'Too many pairing attempts' }, 429)
  }
  await next()
})

// Security headers
app.use('*', async (c, next) => {
  await next()
  c.header('X-Content-Type-Options', 'nosniff')
  c.header('X-Frame-Options', 'DENY')
  c.header('X-XSS-Protection', '1; mode=block')
  c.header('Referrer-Policy', 'no-referrer')
})

app.route('/', createHealthRoutes())
app.route('/', createPairRoutes({ devices, pairs, tokenService, config, wsManager }))
app.route('/', createAuthRoutes({ jwtService, devices }))

import { logger } from './utils/logger.js'

const server = serve({ fetch: app.fetch, port: config.port }, (info) => {
  logger.info('AirTerm relay server started', { port: info.port, domain: config.domain })
})

// Attach WebSocket server
const wss = new WebSocketServer({ noServer: true })

server.on('upgrade', (request: IncomingMessage, socket, head) => {
  const url = new URL(request.url ?? '/', `http://${request.headers.host}`)

  if (url.pathname === '/ws/mac' || url.pathname === '/ws/phone') {
    const token = extractToken(request)
    if (!token || !tokenService.verify(token)) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n')
      socket.destroy()
      return
    }

    wss.handleUpgrade(request, socket, head, (ws) => {
      wsManager.handleConnection(ws, token)
    })
  } else {
    socket.destroy()
  }
})

wsManager.startHeartbeat()

function extractToken(request: IncomingMessage): string | null {
  const auth = request.headers.authorization
  if (auth?.startsWith('Bearer ')) {
    return auth.slice(7)
  }

  const url = new URL(request.url ?? '/', `http://${request.headers.host}`)
  return url.searchParams.get('token')
}

// Graceful shutdown
function shutdown(signal: string) {
  logger.info('Shutting down', { signal })
  wsManager.closeAll()
  server.close(() => {
    db.close()
    logger.info('Server stopped')
    process.exit(0)
  })
  // Force exit after 5 seconds
  setTimeout(() => process.exit(1), 5000)
}

process.on('SIGTERM', () => shutdown('SIGTERM'))
process.on('SIGINT', () => shutdown('SIGINT'))

export { app, wsManager }
