import type { Request, Response } from 'express'
import { isAdaptyWebhookAuthorized } from '../../lib/adapty'
import * as service from './plans.service'

export async function getPlans(req: Request, res: Response) {
  res.json(await service.getPlansOverview(req.user!.id))
}

export async function syncPlan(req: Request, res: Response) {
  try {
    res.json(await service.syncPlanFromAdapty(req.user!.id))
  } catch (error) {
    if (error instanceof service.AdaptyNotConfiguredError) {
      res.status(503).json({ error: error.message })
      return
    }
    console.error('Plan sync failed:', error)
    res.status(502).json({ error: 'Could not reach the subscription service' })
  }
}

export async function adaptyWebhook(req: Request, res: Response) {
  const header = req.headers.authorization
  if (!isAdaptyWebhookAuthorized(typeof header === 'string' ? header : undefined)) {
    res.status(401).json({ error: 'Invalid webhook authorization' })
    return
  }

  // Adapty checks the URL with an empty body when the webhook is saved.
  const body = req.body
  if (!body || (typeof body === 'object' && Object.keys(body).length === 0)) {
    res.json({ ok: true })
    return
  }

  try {
    const result = await service.processAdaptyWebhook(body)
    res.json({ ok: true, ...result })
  } catch (error) {
    // A non-2xx makes Adapty retry the event later.
    console.error('Adapty webhook failed:', error)
    res.status(500).json({ error: 'Webhook processing failed' })
  }
}
