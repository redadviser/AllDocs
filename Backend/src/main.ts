import 'dotenv/config'
import cookieParser from 'cookie-parser'
import cors from 'cors'
import express from 'express'
import { authRouter } from './modules/auth/auth.routes'

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

app.use('/api/auth', authRouter)

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
