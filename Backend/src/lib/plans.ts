import { sql } from './db'

// AllDocs plans. `id` is what profiles.plan stores (and what the Adapty
// access levels are called); `name` is what the app shows. Documents stay on
// the phone, so `storageBytes` is how much the app lets a library hold, not
// space on a server.
export type PlanId = 'free' | 'premium' | 'pro'
export type BillingPeriod = 'monthly' | 'yearly'

export type PlanFeature =
  | 'autoBackup'
  | 'unlimitedReminders'
  | 'watermark'
  | 'pdfTools'
  | 'hiddenAlbums'
  | 'deviceSync'
  | 'secureSharing'
  | 'documentRequests'
  | 'aiAssistant'
  | 'prioritySupport'

export interface Plan {
  id: PlanId
  name: string
  // Reference prices (EUR, VAT included). The app shows the store's own
  // localized price when it has it.
  priceMonthlyCents: number
  priceYearlyCents: number
  currency: 'EUR'
  storageBytes: number
  // null = no limit.
  maxActiveReminders: number | null
  maxDevices: number
  features: PlanFeature[]
}

const MB = 1024 * 1024
const GB = 1024 * MB

const FOLIO_FEATURES: PlanFeature[] = [
  'autoBackup',
  'unlimitedReminders',
  'watermark',
  'pdfTools',
  'hiddenAlbums',
]

export const PLANS: Plan[] = [
  {
    id: 'free',
    name: 'Pocket',
    priceMonthlyCents: 0,
    priceYearlyCents: 0,
    currency: 'EUR',
    storageBytes: 500 * MB,
    maxActiveReminders: 3,
    maxDevices: 1,
    features: [],
  },
  {
    id: 'premium',
    name: 'Folio',
    priceMonthlyCents: 199,
    priceYearlyCents: 1599,
    currency: 'EUR',
    storageBytes: 5 * GB,
    maxActiveReminders: null,
    maxDevices: 2,
    features: FOLIO_FEATURES,
  },
  {
    id: 'pro',
    name: 'Vault',
    priceMonthlyCents: 499,
    priceYearlyCents: 3999,
    currency: 'EUR',
    storageBytes: 50 * GB,
    maxActiveReminders: null,
    maxDevices: 3,
    features: [
      ...FOLIO_FEATURES,
      'deviceSync',
      'secureSharing',
      'documentRequests',
      'aiAssistant',
      'prioritySupport',
    ],
  },
]

// Features a plan lists that the app doesn't have yet; the app marks them
// "coming soon". Remove one from here when it ships.
export const COMING_SOON_FEATURES: PlanFeature[] = [
  'deviceSync',
  'secureSharing',
  'documentRequests',
  'aiAssistant',
]

export function isPlanId(value: unknown): value is PlanId {
  return value === 'free' || value === 'premium' || value === 'pro'
}

export function getPlanById(id: string): Plan {
  return PLANS.find((p) => p.id === id) ?? PLANS[0]
}

export function getPlanRank(planId: string): number {
  const index = PLANS.findIndex((p) => p.id === planId)
  return index >= 0 ? index : 0
}

// Adapty access level id -> plan. Accepts the plan ids themselves and the
// plan names, so the dashboard can use either ("premium" or "folio").
export function planIdFromAccessLevel(accessLevelId: unknown): PlanId | null {
  const value = String(accessLevelId ?? '').trim().toLowerCase()
  if (!value) return null
  if (value === 'pro' || value.includes('vault')) return 'pro'
  if (value === 'premium' || value.includes('folio')) return 'premium'
  return null
}

export function billingPeriodFromProductId(productId: unknown): BillingPeriod {
  const value = String(productId ?? '').toLowerCase()
  return /year|annual|anual|ano/.test(value) ? 'yearly' : 'monthly'
}

// The plan an account has right now: a paid plan whose period ended falls
// back to free even if no webhook said so (expiry is applied lazily).
export const effectivePlanColumn = sql`
  CASE
    WHEN p.plan_expires_at IS NOT NULL AND p.plan_expires_at <= NOW() THEN 'free'
    ELSE p.plan
  END
`
