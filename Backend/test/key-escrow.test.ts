import assert from 'node:assert/strict'
import crypto from 'node:crypto'
import { afterEach, test } from 'node:test'
import { EscrowNotConfiguredError, isEscrowConfigured, open, seal } from '../src/lib/key-escrow'

const saved = { ...process.env }
afterEach(() => {
  process.env = { ...saved }
})

function useSecret(bytes = 32) {
  process.env.NODE_ENV = 'test'
  process.env.KEY_ESCROW_SECRET = crypto.randomBytes(bytes).toString('base64')
}

test('a sealed key opens for the same account', () => {
  useSecret()
  const key = crypto.randomBytes(32)
  assert.deepEqual(open('user-a', seal('user-a', key)), key)
})

test('a sealed key does not open for another account', () => {
  useSecret()
  const sealed = seal('user-a', crypto.randomBytes(32))
  assert.throws(() => open('user-b', sealed))
})

test('a changed byte is detected', () => {
  useSecret()
  const [version, iv, ciphertext, tag] = seal('user-a', crypto.randomBytes(32)).split('.')
  const bytes = Buffer.from(ciphertext, 'base64url')
  bytes[0] ^= 1
  assert.throws(() => open('user-a', [version, iv, bytes.toString('base64url'), tag].join('.')))
})

test('a secret that is not 32 bytes is refused', () => {
  useSecret(31)
  assert.throws(() => seal('user-a', crypto.randomBytes(32)), /32 bytes/)
  assert.equal(isEscrowConfigured(), false)
})

test('outside development, a missing secret is an error, not a fallback', () => {
  process.env.NODE_ENV = 'production'
  delete process.env.KEY_ESCROW_SECRET
  assert.throws(() => seal('user-a', crypto.randomBytes(32)), EscrowNotConfiguredError)
  assert.equal(isEscrowConfigured(), false)
  delete process.env.NODE_ENV // unset counts as production too
  assert.equal(isEscrowConfigured(), false)
})
