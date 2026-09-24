import postgres from 'postgres'

// AllDocs' own database: accounts (users/profiles), devices, and later
// vaults/documents_metadata/reminders/subscriptions per the product roadmap.
const db = process.env.POSTGRES_DB || 'alldocs'
const user = process.env.POSTGRES_USER || 'alldocs'
const password = process.env.POSTGRES_PASSWORD || ''
const host = process.env.POSTGRES_HOST || 'localhost'
const port = Number(process.env.POSTGRES_PORT || '5432')

export const sql = postgres({
  host,
  port,
  database: db,
  username: user,
  password,
  ssl: false,
})
