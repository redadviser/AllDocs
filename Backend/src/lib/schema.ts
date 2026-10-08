import { readFileSync } from 'fs'
import path from 'path'
import { sql } from './db'

// Creates any missing tables and columns (every statement in schema.sql is
// IF NOT EXISTS), so a fresh deploy or a new table needs no manual SQL.
// The file's own BEGIN/COMMIT are left out: postgres.js refuses them on a
// pooled connection, so the statements run inside sql.begin instead.
export async function ensureSchema() {
  const file = path.resolve(__dirname, '../../scripts/schema.sql')
  const statements = readFileSync(file, 'utf8').replace(/^\s*(BEGIN|COMMIT);\s*$/gim, '')
  await sql.begin((tx) => tx.unsafe(statements))
}
