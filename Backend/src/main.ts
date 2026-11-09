import 'dotenv/config'
import cookieParser from 'cookie-parser'
import cors from 'cors'
import express from 'express'
import swaggerUi from 'swagger-ui-express'
import { openApiSpec } from './docs/openapi'
import { apiLimiter, publicPageLimiter } from './lib/rate-limit'
import { ensureSchema } from './lib/schema'
import { authRouter } from './modules/auth/auth.routes'
import { configRouter } from './modules/config/config.routes'
import { passwordRouter, resetPageRouter } from './modules/password/password.routes'
import { devicesRouter } from './modules/devices/devices.routes'
import { adaptyWebhookRouter, plansRouter } from './modules/plans/plans.routes'
import { assistantRouter } from './modules/assistant/assistant.routes'
import { requestPageRouter, requestsRouter } from './modules/requests/requests.routes'
import { purgeOld as purgeOldRequests } from './modules/requests/requests.service'
import { sharePageRouter, sharesRouter } from './modules/shares/shares.routes'
import { purgeOld as purgeOldShares } from './modules/shares/shares.service'
import { syncRouter } from './modules/sync/sync.routes'
import { accountRouter, deletionPageRouter } from './modules/account/account.routes'
import { hiddenPinPageRouter, hiddenPinRouter } from './modules/hidden-pin/hidden-pin.routes'
import { purgeOld as purgeOldSync } from './modules/sync/sync.service'

const app = express()

// One proxy in front (CapRover's nginx): req.ip is the address it saw.
app.set('trust proxy', 1)
app.disable('x-powered-by')

// Defaults for every answer; the HTML pages add their own CSP.
app.use((_req, res, next) => {
  res.set({
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'no-referrer',
    'Strict-Transport-Security': 'max-age=31536000',
    'Cross-Origin-Opener-Policy': 'same-origin',
  })
  next()
})

// The app isn't a browser and the pages call their own origin, so no
// other site may call the API with someone's cookie unless listed here.
const corsOrigins = (process.env.CORS_ORIGIN ?? '')
  .split(',')
  .map((v) => v.trim())
  .filter(Boolean)
app.use(cors({ origin: corsOrigins.length > 0 ? corsOrigins : false, credentials: true }))

app.use(cookieParser())
app.use('/api', apiLimiter)
app.use(['/r/:token', '/s/:token'], publicPageLimiter)
// Before the JSON/form parsers: an upload's body is the raw file, whatever
// content type the browser gives it.
app.use(requestPageRouter)
app.use(sharePageRouter)
app.use(express.json({ limit: '20mb' }))
app.use(express.urlencoded({ extended: true, limit: '20mb' }))

app.get('/health', (_req, res) => {
  res.json({ ok: true })
})

// API docs (Swagger UI). Off unless DOCS_ENABLED=true (local development):
// a public map of the API only helps someone probing it.
if (process.env.DOCS_ENABLED === 'true') {
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

app.use('/api/auth/password', passwordRouter)
app.use('/api/auth', authRouter)
app.use(resetPageRouter)
app.use(deletionPageRouter)
app.use('/api/config', configRouter)
app.use('/api/devices', devicesRouter)
app.use('/api/plans', plansRouter)
app.use('/api/adapty', adaptyWebhookRouter)
app.use('/api/assistant', assistantRouter)
app.use('/api/requests', requestsRouter)
app.use('/api/shares', sharesRouter)
app.use('/api/sync', syncRouter)
app.use('/api/account', accountRouter)
app.use('/api/security/hidden-pin-reset', hiddenPinRouter)
app.use(hiddenPinPageRouter)

app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' })
})

app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error(err)
  res.status(500).json({ error: 'Internal server error' })
})

const port = Number(process.env.PORT || 3000)
ensureSchema()
  .catch((error) => {
    // Keep serving: the tables may already exist and the DB be briefly
    // unreachable; requests will surface a real problem.
    console.error('ensureSchema failed:', error)
  })
  .finally(() => {
    app.listen(port, () => {
      console.log(`Server running on port ${port}`)
    })
    // Uploaded files nobody collected, long-expired requests, files of
    // share links that stopped working, and sync data every device has.
    const purge = async () => {
      for (const [name, run] of [
        ['purgeOldRequests', purgeOldRequests],
        ['purgeOldShares', purgeOldShares],
        ['purgeOldSync', purgeOldSync],
      ] as const) {
        await run().catch((error) => console.error(`${name} failed:`, error))
      }
    }
    purge()
    setInterval(purge, 60 * 60 * 1000).unref()
  })
