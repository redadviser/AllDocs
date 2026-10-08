import { sql } from '../../lib/db'
import {
  type AdaptyAccessLevel,
  fetchAdaptyAccessLevels,
  isAccessLevelActive,
  isAdaptyServerApiConfigured,
} from '../../lib/adapty'
import {
  type BillingPeriod,
  type PlanId,
  COMING_SOON_FEATURES,
  PLANS,
  billingPeriodFromProductId,
  effectivePlanColumn,
  getPlanRank,
  planIdFromAccessLevel,
} from '../../lib/plans'

export class AdaptyNotConfiguredError extends Error {
  constructor() {
    super('Subscriptions are not configured on this server')
  }
}

interface PlanState {
  planId: PlanId
  billingPeriod: BillingPeriod
  expiresAt: Date | null
}

const FREE_STATE: PlanState = { planId: 'free', billingPeriod: 'monthly', expiresAt: null }

export async function getPlansOverview(userId: string) {
  const rows = await sql`
    SELECT ${effectivePlanColumn} AS plan, p.plan_billing_period, p.plan_expires_at
    FROM profiles p
    WHERE p.id = ${userId}
  `
  const row = rows[0]
  const currentPlanId = ((row?.plan as string | undefined) ?? 'free') as PlanId
  return {
    currentPlanId,
    billingPeriod: currentPlanId === 'free' ? null : ((row?.plan_billing_period as string) ?? 'monthly'),
    expiresAt: currentPlanId === 'free' ? null : ((row?.plan_expires_at as Date | null) ?? null),
    plans: PLANS,
    comingSoon: COMING_SOON_FEATURES,
  }
}

// The highest plan among the account's active access levels.
function stateFromAccessLevels(levels: AdaptyAccessLevel[]): PlanState {
  let best: PlanState = FREE_STATE
  for (const level of levels) {
    const planId = planIdFromAccessLevel(level.access_level_id)
    if (!planId || !isAccessLevelActive(level)) continue
    if (getPlanRank(planId) <= getPlanRank(best.planId)) continue
    const expiresAt = level.expires_at ? new Date(level.expires_at) : null
    best = {
      planId,
      billingPeriod: billingPeriodFromProductId(level.store_product_id),
      // In a billing grace period the store still grants access past
      // expires_at; leave the expiry open until Adapty reports the outcome.
      expiresAt: expiresAt && expiresAt.getTime() > Date.now() ? expiresAt : null,
    }
  }
  return best
}

async function applyPlanState(userId: string, state: PlanState) {
  await sql`
    UPDATE profiles
    SET plan = ${state.planId},
        plan_billing_period = ${state.billingPeriod},
        plan_expires_at = ${state.expiresAt},
        plan_updated_at = NOW(),
        updated_at = NOW()
    WHERE id = ${userId}
  `
}

// Asks Adapty what the account is paying for and stores it. The app calls
// this after a purchase or restore, so the plan never depends on what the
// phone claims.
export async function syncPlanFromAdapty(userId: string) {
  if (!isAdaptyServerApiConfigured()) throw new AdaptyNotConfiguredError()
  const levels = await fetchAdaptyAccessLevels(userId)
  await applyPlanState(userId, stateFromAccessLevels(levels))
  return getPlansOverview(userId)
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {}
}

function asString(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null
}

// Without the server-side API, the event itself decides: an access level
// that is granted sets its plan; one that is taken away only downgrades the
// account if it was that plan (an expiring Folio must not undo a Vault).
async function applyEvent(userId: string, eventType: string, properties: Record<string, unknown>) {
  const planId = planIdFromAccessLevel(properties.access_level_id)
  if (!planId) return

  const expiresAtRaw = asString(properties.expires_at)
  const expiresAt = expiresAtRaw ? new Date(expiresAtRaw) : null
  const revoked =
    properties.profile_has_access_level === false ||
    properties.is_refund === true ||
    eventType.endsWith('_refunded') ||
    eventType === 'subscription_expired' ||
    eventType === 'trial_expired' ||
    (expiresAt !== null && expiresAt.getTime() <= Date.now())

  if (revoked) {
    await sql`
      UPDATE profiles
      SET plan = 'free', plan_expires_at = NULL, plan_updated_at = NOW(), updated_at = NOW()
      WHERE id = ${userId} AND plan = ${planId}
    `
    return
  }

  await applyPlanState(userId, {
    planId,
    billingPeriod: billingPeriodFromProductId(properties.vendor_product_id),
    expiresAt,
  })
}

export async function processAdaptyWebhook(body: unknown) {
  const event = asRecord(body)
  const eventType = asString(event.event_type) ?? 'unknown'
  const customerUserId = asString(event.customer_user_id)
  const properties = asRecord(event.event_properties)

  const users = customerUserId
    ? await sql`SELECT id FROM users WHERE id = ${customerUserId}`
    : []
  const userId = (users[0]?.id as string | undefined) ?? null

  await sql`
    INSERT INTO subscription_events (user_id, customer_user_id, event_type, environment, payload)
    VALUES (
      ${userId},
      ${customerUserId},
      ${eventType},
      ${asString(properties.environment)},
      ${sql.json(event as Parameters<typeof sql.json>[0])}
    )
  `

  if (!userId) return { eventType, applied: false }

  // Adapty's own view of the profile is the source of truth when we can ask
  // for it: it settles out-of-order events and upgrades/downgrades in one go.
  if (isAdaptyServerApiConfigured()) {
    await syncPlanFromAdapty(userId)
  } else {
    await applyEvent(userId, eventType, properties)
  }
  return { eventType, applied: true }
}
