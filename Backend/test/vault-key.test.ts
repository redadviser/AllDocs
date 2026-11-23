import assert from 'node:assert/strict'
import crypto from 'node:crypto'
import type { AddressInfo } from 'node:net'
import { after, before, test } from 'node:test'

// Needs a throwaway Postgres: TEST_POSTGRES_PORT (plus the usual
// POSTGRES_* for user/password/db). Skipped without it, so `npm test`
// never writes test accounts into a real database.
const port = process.env.TEST_POSTGRES_PORT
const skip = port ? false : 'set TEST_POSTGRES_PORT to run against a test database'

let base = ''
let close = async () => {}
let sql: typeof import('../src/lib/db').sql
let signUp: typeof import('../src/lib/auth').signUp

before(async () => {
  if (!port) return
  process.env.NODE_ENV = 'test'
  process.env.POSTGRES_PORT = port
  process.env.KEY_ESCROW_SECRET = crypto.randomBytes(32).toString('base64')
  const express = (await import('express')).default
  const cookieParser = (await import('cookie-parser')).default
  ;({ sql } = await import('../src/lib/db'))
  ;({ signUp } = await import('../src/lib/auth'))
  const { ensureSchema } = await import('../src/lib/schema')
  const { vaultKeyRouter } = await import('../src/modules/vault-key/vault-key.routes')
  await ensureSchema()
  const app = express()
  app.use(cookieParser(), express.json())
  app.use('/api/security/vault-key', vaultKeyRouter)
  const server = app.listen(0)
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}/api/security/vault-key`
  close = async () => {
    server.close()
    await sql.end()
  }
})

after(() => close())

// Signed in from a phone (with a device id), as the app does.
async function newAccount() {
  const deviceId = crypto.randomUUID()
  const { user, token } = await signUp(
    `vault-${crypto.randomUUID()}@test.local`,
    'password123',
    undefined,
    deviceId
  )
  await sql`INSERT INTO devices (id, user_id) VALUES (${deviceId}, ${user.id})`
  return { id: user.id, cookie: `session_token=${token}` }
}

async function sessionWithoutDevice(userId: string, email: string) {
  const { SignJWT } = await import('jose')
  const secret = new TextEncoder().encode('default-dev-secret-change-in-production')
  const token = await new SignJWT({ sub: userId, email })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('1h')
    .sign(secret)
  return `session_token=${token}`
}

function call(method: string, cookie?: string, body?: unknown) {
  return fetch(base, {
    method,
    headers: { 'content-type': 'application/json', ...(cookie ? { cookie } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
}

const keyBody = () => ({
  key: crypto.randomBytes(32).toString('base64'),
  keyCheck: crypto.randomBytes(32).toString('hex'),
})

test('without a session: 401', { skip }, async () => {
  assert.equal((await call('GET')).status, 401)
  assert.equal((await call('PUT', undefined, keyBody())).status, 401)
})

test('stored once, never replaced, read back as stored', { skip }, async () => {
  const { cookie } = await newAccount()
  assert.equal((await call('GET', cookie)).status, 404)

  const first = keyBody()
  assert.equal((await call('PUT', cookie, first)).status, 201)
  assert.equal((await call('PUT', cookie, first)).status, 200)
  assert.equal((await call('PUT', cookie, keyBody())).status, 409)

  const read = await call('GET', cookie)
  assert.equal(read.status, 200)
  assert.equal(read.headers.get('cache-control'), 'no-store')
  assert.deepEqual(await read.json(), first)
})

test('the key is only handed to a fresh session from a phone', { skip }, async () => {
  const { id, cookie } = await newAccount()
  assert.equal((await call('PUT', cookie, keyBody())).status, 201)
  assert.equal((await call('GET', cookie)).status, 200)
  const [{ email }] = await sql`SELECT email FROM users WHERE id = ${id}`
  const noDevice = await sessionWithoutDevice(id, email as string)
  const refused = await call('GET', noDevice)
  assert.equal(refused.status, 403)
  assert.equal((await refused.json()).code, 'reauth')
})

test('a malformed key is refused', { skip }, async () => {
  const { cookie } = await newAccount()
  assert.equal((await call('PUT', cookie, { key: 'abc', keyCheck: 'x' })).status, 400)
  assert.equal((await call('GET', cookie)).status, 404)
})

test('deleting the account deletes the copy', { skip }, async () => {
  const { id, cookie } = await newAccount()
  assert.equal((await call('PUT', cookie, keyBody())).status, 201)
  await sql`DELETE FROM users WHERE id = ${id}`
  const rows = await sql`SELECT 1 FROM vault_keys WHERE user_id = ${id}`
  assert.equal(rows.length, 0)
})

test('the 21st call in 15 minutes is refused', { skip }, async () => {
  const { cookie } = await newAccount()
  for (let i = 0; i < 20; i++) assert.equal((await call('GET', cookie)).status, 404)
  assert.equal((await call('GET', cookie)).status, 429)
})
