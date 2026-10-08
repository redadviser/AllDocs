import Anthropic from '@anthropic-ai/sdk'
import type { Request, Response } from 'express'
import {
  AssistantIncompleteError,
  AssistantRefusedError,
  isAssistantConfigured,
} from '../../lib/assistant'
import * as service from './assistant.service'

async function handle(res: Response, work: () => Promise<unknown>) {
  if (!isAssistantConfigured()) {
    res.status(503).json({ error: 'The assistant is not configured on this server' })
    return
  }
  try {
    res.json(await work())
  } catch (error) {
    if (error instanceof service.AssistantLimitError) {
      res.status(error.status).json({ error: error.message })
    } else if (error instanceof AssistantRefusedError) {
      res.status(422).json({ error: error.message, code: 'refused' })
    } else if (error instanceof AssistantIncompleteError) {
      res.status(502).json({ error: error.message, code: 'incomplete' })
    } else if (error instanceof Anthropic.RateLimitError) {
      res.status(503).json({ error: 'The assistant is busy, try again shortly' })
    } else if (error instanceof Anthropic.APIError) {
      console.error('Assistant API error:', error.status, error.message)
      res.status(502).json({ error: 'The assistant could not answer right now' })
    } else {
      console.error('Assistant failed:', error)
      res.status(500).json({ error: 'Internal server error' })
    }
  }
}

export async function usage(req: Request, res: Response) {
  res.json(await service.getUsage(req.user!.id))
}

export function ask(req: Request, res: Response) {
  return handle(res, () =>
    service.ask(
      req.user!,
      String(req.body?.question ?? ''),
      service.validateDocuments(req.body?.documents),
      req.body?.language
    )
  )
}

export function extract(req: Request, res: Response) {
  return handle(res, () =>
    service.extract(
      req.user!,
      service.validateDocuments([req.body?.document])[0],
      req.body?.language
    )
  )
}

export function summarize(req: Request, res: Response) {
  return handle(res, () =>
    service.summarize(
      req.user!,
      service.validateDocuments([req.body?.document])[0],
      req.body?.language
    )
  )
}
