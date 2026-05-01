import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { serve } from '@hono/node-server'
import { WebSocketServer } from 'ws'
import type { IncomingMessage } from 'node:http'
import { createDatabase } from '../../db/init.js'
import { createDeviceRepository } from '../../db/devices.js'
import { createPairRepository } from '../../db/pairs.js'
import { createTokenService } from '../../auth/token.js'
import { createWSManager } from '../../ws/manager.js'
import { createHealthRoutes } from '../../routes/health.js'
import { createPairRoutes } from '../../routes/pair.js'
import type { Config } from '../../config.js'

const TEST_SECRET = 'test-secret-that-is-at-least-32-chars-long!'

export interface TestServer {
  readonly url: string
  readonly wsUrl: string
  close(): Promise<void>
}

export function startTestServer(): Promise<TestServer> {
  return new Promise((resolve) => {
    const db = createDatabase(':memory:')
    const devices = createDeviceRepository(db)
    const pairs = createPairRepository(db)
    const tokenService = createTokenService(TEST_SECRET)
    const wsManager = createWSManager({ tokenService, devices, pairs })
    const config: Config = {
      port: 0,
      jwtSecret: TEST_SECRET,
      pairCodeTtl: 300,
      dbPath: ':memory:',
      domain: 'localhost',
    }

    const app = new Hono()
    app.use('*', cors())
    app.route('/', createHealthRoutes({ devices, pairs, wsManager }))
    app.route('/', createPairRoutes({ devices, pairs, tokenService, config, wsManager }))

    const wss = new WebSocketServer({ noServer: true })

    const server = serve({ fetch: app.fetch, port: 0 }, (info) => {
      const port = info.port
      wsManager.startHeartbeat()

      resolve({
        url: `http://localhost:${port}`,
        wsUrl: `ws://localhost:${port}`,
        close() {
          return new Promise<void>((done) => {
            wsManager.closeAll()
            server.close(() => {
              wss.close()
              db.close()
              done()
            })
          })
        },
      })
    })

    server.on('upgrade', (request: IncomingMessage, socket: any, head: Buffer) => {
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
  })
}

function extractToken(request: IncomingMessage): string | null {
  const auth = request.headers.authorization
  if (auth?.startsWith('Bearer ')) {
    return auth.slice(7)
  }
  const url = new URL(request.url ?? '/', `http://${request.headers.host}`)
  return url.searchParams.get('token')
}
