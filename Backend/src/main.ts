import 'dotenv/config'
import cookieParser from 'cookie-parser'
import cors from 'cors'
import express from 'express'
import swaggerUi from 'swagger-ui-express'
import { openApiSpec } from './docs/openapi'
import { authRouter } from './modules/auth/auth.routes'
import { configRouter } from './modules/config/config.routes'
import { devicesRouter } from './modules/devices/devices.routes'

const app = express()

app.set('trust proxy', 1)

app.use(
  cors({
    origin: process.env.CORS_ORIGIN?.split(',').map((v) => v.trim()) || true,
    credentials: true,
  })
)

app.use(cookieParser())
app.use(express.json({ limit: '20mb' }))
app.use(express.urlencoded({ extended: true, limit: '20mb' }))

app.get('/health', (_req, res) => {
  res.json({ ok: true })
})

// API docs (Swagger UI). On by default; set DOCS_ENABLED=false to hide
// them on a deployment.
if (process.env.DOCS_ENABLED !== 'false') {
  app.get('/api/docs/openapi.json', (_req, res) => {
    res.json(openApiSpec)
  })
  app.use(
    '/api/docs',
    swaggerUi.serve,
    swaggerUi.setup(openApiSpec, {
      customSiteTitle: 'AllDocs API',
      swaggerOptions: { withCredentials: true, persistAuthorization: true },
    })
  )
}

app.use('/api/auth', authRouter)
app.use('/api/config', configRouter)
app.use('/api/devices', devicesRouter)

app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' })
})

app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error(err)
  res.status(500).json({ error: 'Internal server error' })
})

const port = Number(process.env.PORT || 3000)
app.listen(port, () => {
  console.log(`Server running on port ${port}`)
})
