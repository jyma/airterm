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

const config = loadConfig()
const db = createDatabase(config.dbPath)
const devices = createDeviceRepository(db)
const pairs = createPairRepository(db)
const tokenService = createTokenService(config.jwtSecret)
const wsManager = createWSManager({ tokenService, devices, pairs })

const app = new Hono()

app.use('*', cors())
app.route('/', createHealthRoutes())
app.route('/', createPairRoutes({ devices, pairs, tokenService, config, wsManager }))

const server = serve({ fetch: app.fetch, port: config.port }, (info) => {
  console.log(`AirTerm relay server listening on http://localhost:${info.port}`)
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
process.on('SIGTERM', () => {
  wsManager.closeAll()
  db.close()
  process.exit(0)
})

process.on('SIGINT', () => {
  wsManager.closeAll()
  db.close()
  process.exit(0)
})

export { app, wsManager }
