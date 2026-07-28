import postgres from 'postgres'

// AllDocs' own domain data: devices this phase, later
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

// Shared account identity (the `users` table only). Same Postgres server as
// AllPhotos in production, a different database — AllDocs never reads or
// writes AllPhotos' own domain tables (profiles, albums, photos, shelves).
const accountsDb = process.env.ACCOUNTS_POSTGRES_DB || 'allphotos'
const accountsUser = process.env.ACCOUNTS_POSTGRES_USER || 'allphotos'
const accountsPassword = process.env.ACCOUNTS_POSTGRES_PASSWORD || ''
const accountsHost = process.env.ACCOUNTS_POSTGRES_HOST || 'localhost'
const accountsPort = Number(process.env.ACCOUNTS_POSTGRES_PORT || '5432')

export const accountsSql = postgres({
  host: accountsHost,
  port: accountsPort,
  database: accountsDb,
  username: accountsUser,
  password: accountsPassword,
  ssl: false,
})
