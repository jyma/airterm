import { Hono } from 'hono'

export function createHealthRoutes(): Hono {
  const app = new Hono()

  app.get('/health', (c) => {
    return c.json({
      status: 'ok',
      timestamp: Date.now(),
      version: '0.1.0',
    })
  })

  return app
}
