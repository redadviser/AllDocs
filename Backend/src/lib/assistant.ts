import OpenAI from 'openai'

// The Vault plan's document assistant runs on OpenAI. Only what the app
// sends for one request reaches it — the excerpts of the few documents
// that matter to a question, or one document's text — never the library.
// Requests go through the OpenAI API with `store: false` (not kept for
// later retrieval); nothing here is stored beyond a monthly usage count.

export const ASSISTANT_MODEL = process.env.ASSISTANT_MODEL?.trim() || 'gpt-5.4-mini'

let client: OpenAI | null = null

export function isAssistantConfigured(): boolean {
  return Boolean(process.env.OPENAI_API_KEY?.trim())
}

function openai(): OpenAI {
  return (client ??= new OpenAI())
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

export { OpenAI as AssistantApi }

type JsonSchema = Record<string, unknown>

/// One request whose answer must match [schema] (structured outputs,
/// strict). A refusal or a content-filter stop is AssistantRefusedError;
/// running out of tokens, AssistantIncompleteError.
export async function askForJson<T>(options: {
  system: string
  user: string
  schema: JsonSchema
  effort: 'low' | 'medium' | 'high'
  maxTokens: number
}): Promise<T> {
  const response = await openai().responses.create({
    model: ASSISTANT_MODEL,
    instructions: options.system,
    input: options.user,
    max_output_tokens: options.maxTokens,
    reasoning: { effort: options.effort },
    store: false,
    text: {
      format: {
        type: 'json_schema',
        name: 'answer',
        schema: options.schema,
        strict: true,
      },
    },
  })

  if (response.status === 'incomplete') {
    if (response.incomplete_details?.reason === 'content_filter') {
      throw new AssistantRefusedError()
    }
    throw new AssistantIncompleteError()
  }
  for (const item of response.output) {
    if (item.type !== 'message') continue
    if (item.content.some((part) => part.type === 'refusal')) {
      throw new AssistantRefusedError()
    }
  }
  return JSON.parse(response.output_text) as T
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
