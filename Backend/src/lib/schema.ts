import { readFileSync } from 'fs'
import path from 'path'
import { sql } from './db'

// Creates any missing tables (every statement in schema.sql is
// IF NOT EXISTS), so a fresh deploy or a new table needs no manual SQL.
export async function ensureSchema() {
  const file = path.resolve(__dirname, '../../scripts/schema.sql')
  await sql.unsafe(readFileSync(file, 'utf8'))
}
