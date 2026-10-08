import Anthropic from '@anthropic-ai/sdk'

// The Vault plan's document assistant runs on Claude. Only what the app
// sends for one request reaches it — the excerpts of the few documents
// that matter to a question, or one document's text — never the library.
// Requests go through the Anthropic API under the account's data
// retention settings; nothing here is stored beyond a monthly usage count.

export const ASSISTANT_MODEL = process.env.ASSISTANT_MODEL?.trim() || 'claude-opus-5-5'

let client: Anthropic | null = null

export function isAssistantConfigured(): boolean {
  return Boolean(process.env.ANTHROPIC_API_KEY?.trim())
}

function anthropic(): Anthropic {
  return (client ??= new Anthropic())
}

export class AssistantRefusedError extends Error {
  constructor() {
    super('The assistant could not help with this request')
  }
}

export class AssistantIncompleteError extends Error {
  constructor() {
    super('The assistant answer was cut short')
  }
}

type JsonSchema = Record<string, unknown>

/// One request with a JSON-schema answer. A safety decline is retried on
/// Anthropic's recommended fallback model (`fallbacks: "default"`); if the
/// whole chain declines, AssistantRefusedError.
export async function askForJson<T>(options: {
  system: string
  user: string
  schema: JsonSchema
  effort: 'low' | 'medium' | 'high'
  maxTokens: number
}): Promise<T> {
  const response = await anthropic().beta.messages.create({
    model: ASSISTANT_MODEL,
    max_tokens: options.maxTokens,
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
    system: options.system,
    messages: [{ role: 'user', content: options.user }],
    output_config: {
      effort: options.effort,
      format: { type: 'json_schema', schema: options.schema },
    },
  })

  if (response.stop_reason === 'refusal') throw new AssistantRefusedError()
  if (response.stop_reason === 'max_tokens') throw new AssistantIncompleteError()
  const text = response.content
    .flatMap((block) => (block.type === 'text' ? [block.text] : []))
    .join('')
  return JSON.parse(text) as T
}

/// Wraps a document's text so the model reads it as material, not as
/// instructions (a document could contain text written to look like one).
export function documentBlock(doc: { id: string; title: string; text: string }): string {
  return [
    `<document id="${escapeAttr(doc.id)}" title="${escapeAttr(doc.title)}">`,
    doc.text.replaceAll('</document>', '</ document>'),
    '</document>',
  ].join('\n')
}

function escapeAttr(value: string): string {
  return value.replace(/["<>&]/g, ' ')
}
