// Adapty: the app buys subscriptions through the Adapty SDK (App Store /
// Google Play billing), identifying the buyer with the AllDocs user id as
// `customer_user_id`. This server learns about them two ways: Adapty's
// webhook (POST /api/adapty/webhook) and, when the secret key is set, by
// asking Adapty's server-side API for the profile.

const ADAPTY_API_BASE_URL = process.env.ADAPTY_API_BASE_URL || 'https://api.adapty.io'

export interface AdaptyAccessLevel {
  access_level_id: string
  store?: string | null
  store_product_id?: string | null
  starts_at?: string | null
  expires_at?: string | null
  renewal_cancelled_at?: string | null
  is_in_grace_period?: boolean | null
}

function configuredWebhookAuthValues(): string[] {
  return [
    process.env.ADAPTY_WEBHOOK_AUTH,
    process.env.ADAPTY_WEBHOOK_AUTH_SANDBOX,
  ]
    .map((value) => value?.trim() || '')
    .filter(Boolean)
}

// The webhook is configured in the Adapty dashboard with an Authorization
// header value; requests without that exact value are rejected.
export function isAdaptyWebhookAuthorized(headerValue: string | undefined): boolean {
  const allowed = configuredWebhookAuthValues()
  const received = headerValue?.trim()
  return allowed.length > 0 && !!received && allowed.includes(received)
}

export function isAdaptyServerApiConfigured(): boolean {
  return Boolean(process.env.ADAPTY_SECRET_API_KEY?.trim())
}

// The account's current access levels in Adapty, or [] when Adapty has no
// profile for it (never bought anything).
export async function fetchAdaptyAccessLevels(customerUserId: string): Promise<AdaptyAccessLevel[]> {
  const apiKey = process.env.ADAPTY_SECRET_API_KEY?.trim()
  if (!apiKey) throw new Error('ADAPTY_SECRET_API_KEY is not configured')

  const response = await fetch(`${ADAPTY_API_BASE_URL}/api/v2/server-side-api/profile/`, {
    headers: {
      Authorization: `Api-Key ${apiKey}`,
      'adapty-customer-user-id': customerUserId,
    },
  })
  if (response.status === 404) return []
  if (!response.ok) {
    const body = await response.text()
    throw new Error(`Adapty profile request failed with ${response.status}: ${body}`)
  }

  const json = (await response.json()) as { data?: { access_levels?: AdaptyAccessLevel[] } }
  return json.data?.access_levels ?? []
}

export function isAccessLevelActive(level: AdaptyAccessLevel, now = Date.now()): boolean {
  const startsAt = level.starts_at ? Date.parse(level.starts_at) : NaN
  if (!Number.isNaN(startsAt) && startsAt > now) return false
  // No expiry = lifetime.
  if (!level.expires_at) return true
  const expiresAt = Date.parse(level.expires_at)
  return Number.isNaN(expiresAt) || expiresAt > now || level.is_in_grace_period === true
}
