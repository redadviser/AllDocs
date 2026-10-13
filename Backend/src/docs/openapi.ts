// OpenAPI description of the AllDocs backend, served by Swagger UI at
// /api/docs (see main.ts). Keep it in step with the routers in src/modules.

const error = {
  type: 'object',
  properties: { error: { type: 'string' } },
} as const

const success = {
  type: 'object',
  properties: { success: { type: 'boolean', example: true } },
} as const

const userResponse = {
  type: 'object',
  properties: { user: { $ref: '#/components/schemas/User' } },
} as const

const sessionCookieHeader = {
  'Set-Cookie': {
    description: 'Session JWT (`session_token`, httpOnly, 30 days).',
    schema: { type: 'string', example: 'session_token=eyJ...; Path=/; HttpOnly' },
  },
}

export const openApiSpec = {
  openapi: '3.0.3',
  info: {
    title: 'AllDocs API',
    version: '0.1.0',
    description: [
      'Backend of the AllDocs app: accounts, sessions/devices, subscription',
      'plans and app configuration. Documents themselves stay on the phone.',
      '',
      'Authentication is a `session_token` cookie. In this page, calling a',
      'login endpoint with **Try it out** sets the cookie in the browser, so',
      'the protected endpoints work right after.',
      '',
      '**OAuth flows and callbacks.** None of the sign-ins redirect through',
      'this server:',
      '- *Sign in with Google*: the app gets a Google **ID token** natively',
      '  (Google Sign-In SDK) and posts it to `POST /api/auth/google/signin`,',
      '  which verifies it and opens the session. There is no redirect',
      '  callback URL on the backend.',
      '- *Google Drive, Dropbox*: authorized on the phone (PKCE);',
      '  the OAuth redirect is the app\'s own scheme',
      '  `com.alldocs.app:/oauth2redirect`, and the tokens stay in the',
      '  phone\'s keystore. The backend only hands out the public client ids',
      '  (`GET /api/config/cloud`) and never sees users\' cloud tokens.',
    ].join('\n'),
  },
  servers: [{ url: '/', description: 'This server' }],
  tags: [
    { name: 'Auth', description: 'AllDocs accounts and sessions' },
    { name: 'Devices', description: 'Signed-in devices (sessions) of the current user' },
    { name: 'Plans', description: 'Subscription plans (Pocket, Folio, Vault), bought through Adapty' },
    { name: 'Assistant', description: 'Document assistant (Vault plan), powered by OpenAI' },
    { name: 'Requests', description: 'Ask someone else for documents through a link (Vault plan)' },
    { name: 'Shares', description: 'Share a document behind a secure link: expires, optional code, revocable (Vault plan)' },
    { name: 'Sync', description: 'Device sync relay, end-to-end encrypted on the phones (Vault plan)' },
    { name: 'Config', description: 'Public app configuration' },
    { name: 'Health' },
  ],
  components: {
    securitySchemes: {
      sessionCookie: { type: 'apiKey', in: 'cookie', name: 'session_token' },
    },
    schemas: {
      User: {
        type: 'object',
        properties: {
          id: { type: 'string', format: 'uuid' },
          email: { type: 'string', format: 'email' },
          displayName: { type: 'string', nullable: true },
          plan: { type: 'string', example: 'free' },
          avatarUrl: { type: 'string', nullable: true },
        },
      },
      DeviceInfo: {
        type: 'object',
        description:
          'Optional. With an `id`, the session is tied to this device and can be revoked from Devices.',
        properties: {
          id: { type: 'string', example: '3f1c2a9e-8b7d-4e21-9a55-0c1d2e3f4a5b' },
          platform: { type: 'string', example: 'android' },
          name: { type: 'string', example: 'Pixel 8' },
        },
      },
      Device: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          platform: { type: 'string' },
          name: { type: 'string', nullable: true },
          lastSeenAt: { type: 'string', format: 'date-time' },
          createdAt: { type: 'string', format: 'date-time' },
        },
      },
      Plan: {
        type: 'object',
        properties: {
          id: { type: 'string', enum: ['free', 'premium', 'pro'] },
          name: { type: 'string', example: 'Folio' },
          priceMonthlyCents: { type: 'integer', example: 199 },
          priceYearlyCents: { type: 'integer', example: 1599 },
          currency: { type: 'string', example: 'EUR' },
          storageBytes: { type: 'integer', description: 'How much the library may hold on the phone', example: 5368709120 },
          maxActiveReminders: { type: 'integer', nullable: true, description: 'null = unlimited', example: null },
          maxDevices: { type: 'integer', example: 2 },
          features: {
            type: 'array',
            items: {
              type: 'string',
              enum: [
                'autoBackup', 'unlimitedReminders', 'watermark', 'pdfTools', 'hiddenAlbums',
                'deviceSync', 'secureSharing', 'documentRequests', 'aiAssistant', 'prioritySupport',
              ],
            },
          },
        },
      },
      PlansOverview: {
        type: 'object',
        properties: {
          currentPlanId: { type: 'string', enum: ['free', 'premium', 'pro'] },
          billingPeriod: { type: 'string', enum: ['monthly', 'yearly'], nullable: true },
          expiresAt: { type: 'string', format: 'date-time', nullable: true, description: 'End of the paid period, when known' },
          plans: { type: 'array', items: { $ref: '#/components/schemas/Plan' } },
          comingSoon: {
            type: 'array',
            items: { type: 'string' },
            description: 'Features listed by plans that the app does not have yet',
          },
        },
      },
      CloudConfig: {
        type: 'object',
        properties: {
          google: {
            type: 'object',
            properties: {
              webClientId: { type: 'string', nullable: true },
              iosClientId: { type: 'string', nullable: true },
            },
          },
          dropbox: {
            type: 'object',
            properties: { appKey: { type: 'string', nullable: true } },
          },
        },
      },
    },
  },
  paths: {
    '/health': {
      get: {
        tags: ['Health'],
        summary: 'Liveness check',
        responses: {
          200: {
            description: 'Server is up',
            content: {
              'application/json': {
                schema: { type: 'object', properties: { ok: { type: 'boolean' } } },
              },
            },
          },
        },
      },
    },
    '/api/auth/signup': {
      post: {
        tags: ['Auth'],
        summary: 'Create an account (email + password)',
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: {
                type: 'object',
                required: ['email', 'password'],
                properties: {
                  email: { type: 'string', format: 'email' },
                  password: { type: 'string', minLength: 6 },
                  displayName: { type: 'string' },
                  device: { $ref: '#/components/schemas/DeviceInfo' },
                },
              },
            },
          },
        },
        responses: {
          200: {
            description: 'Account created and signed in',
            headers: sessionCookieHeader,
            content: { 'application/json': { schema: userResponse } },
          },
          400: {
            description: 'Missing fields, short password or email already registered',
            content: { 'application/json': { schema: error } },
          },
        },
      },
    },
    '/api/auth/login': {
      post: {
        tags: ['Auth'],
        summary: 'Sign in with email + password',
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: {
                type: 'object',
                required: ['email', 'password'],
                properties: {
                  email: { type: 'string', format: 'email' },
                  password: { type: 'string' },
                  device: { $ref: '#/components/schemas/DeviceInfo' },
                },
              },
            },
          },
        },
        responses: {
          200: {
            description: 'Signed in',
            headers: sessionCookieHeader,
            content: { 'application/json': { schema: userResponse } },
          },
          400: { description: 'Missing fields', content: { 'application/json': { schema: error } } },
          401: { description: 'Invalid email or password', content: { 'application/json': { schema: error } } },
        },
      },
    },
    '/api/auth/google/signin': {
      post: {
        tags: ['Auth'],
        summary: 'Sign in with Google',
        description: [
          'This is the Google login endpoint; there is no redirect callback.',
          'The app signs in with the native Google Sign-In SDK and sends the',
          'resulting **ID token** here. The server verifies its signature,',
          'expiry and audience (one of `GOOGLE_SIGNIN_WEB_CLIENT_ID`,',
          '`GOOGLE_SIGNIN_IOS_CLIENT_ID`, `GOOGLE_SIGNIN_ANDROID_CLIENT_ID`),',
          'then signs into, or creates, the account with that verified email.',
          'An existing password account with the same email is the same identity.',
        ].join('\n'),
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: {
                type: 'object',
                required: ['idToken'],
                properties: {
                  idToken: { type: 'string', description: 'Google ID token (JWT) from the Google Sign-In SDK' },
                  device: { $ref: '#/components/schemas/DeviceInfo' },
                },
              },
            },
          },
        },
        responses: {
          200: {
            description: 'Signed in',
            headers: sessionCookieHeader,
            content: { 'application/json': { schema: userResponse } },
          },
          400: { description: 'idToken missing', content: { 'application/json': { schema: error } } },
          401: {
            description: 'Invalid/expired token, unverified email, or Google sign-in not configured on the server',
            content: { 'application/json': { schema: error } },
          },
        },
      },
    },
    '/api/auth/password/forgot': {
      post: {
        tags: ['Auth'],
        summary: 'Forgot password: email a reset link',
        description: [
          'If an account has this email, sends it a link to',
          '`/reset-password?token=...` (valid 1 hour, single use). Always',
          'answers 200, so it can\'t reveal which emails have an account.',
          'At most one email per address per minute.',
        ].join('\n'),
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: {
                type: 'object',
                required: ['email'],
                properties: {
                  email: { type: 'string', format: 'email' },
                  lang: { type: 'string', enum: ['pt', 'en', 'es', 'fr'], description: 'Language of the email and page' },
                },
              },
            },
          },
        },
        responses: {
          200: { description: 'Request accepted', content: { 'application/json': { schema: success } } },
          400: { description: 'email missing', content: { 'application/json': { schema: error } } },
        },
      },
    },
    '/api/auth/password/reset': {
      post: {
        tags: ['Auth'],
        summary: 'Set a new password with a reset token',
        description:
          'Used by the /reset-password page. Also ends every session of the account (all devices).',
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: {
                type: 'object',
                required: ['token', 'password'],
                properties: {
                  token: { type: 'string' },
                  password: { type: 'string', minLength: 6 },
                },
              },
            },
          },
        },
        responses: {
          200: { description: 'Password changed', content: { 'application/json': { schema: success } } },
          400: {
            description: 'Missing fields, short password, or invalid/expired/used token',
            content: { 'application/json': { schema: error } },
          },
        },
      },
    },
    '/reset-password': {
      get: {
        tags: ['Auth'],
        summary: 'Reset password page (HTML, opened from the email)',
        parameters: [
          { name: 'token', in: 'query', required: true, schema: { type: 'string' } },
          { name: 'lang', in: 'query', required: false, schema: { type: 'string', enum: ['pt', 'en', 'es', 'fr'] } },
        ],
        responses: {
          200: { description: 'The form, or an "invalid or expired link" message', content: { 'text/html': {} } },
        },
      },
    },
    '/api/auth/logout': {
      post: {
        tags: ['Auth'],
        summary: 'Sign out (clears the session cookie)',
        responses: {
          200: { description: 'Signed out', content: { 'application/json': { schema: success } } },
        },
      },
    },
    '/api/auth/me': {
      get: {
        tags: ['Auth'],
        summary: 'Current user',
        security: [{ sessionCookie: [] }],
        responses: {
          200: { description: 'Signed in', content: { 'application/json': { schema: userResponse } } },
          401: {
            description: 'No valid session (missing, expired or revoked)',
            content: {
              'application/json': {
                schema: { type: 'object', properties: { user: { type: 'object', nullable: true, example: null } } },
              },
            },
          },
        },
      },
    },
    '/api/devices': {
      get: {
        tags: ['Devices'],
        summary: 'List signed-in devices',
        security: [{ sessionCookie: [] }],
        responses: {
          200: {
            description: 'Devices, most recently seen first',
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  properties: {
                    devices: { type: 'array', items: { $ref: '#/components/schemas/Device' } },
                  },
                },
              },
            },
          },
          401: { description: 'Not authenticated', content: { 'application/json': { schema: error } } },
        },
      },
      delete: {
        tags: ['Devices'],
        summary: 'End every session (all devices, including this one)',
        security: [{ sessionCookie: [] }],
        responses: {
          200: { description: 'All sessions ended', content: { 'application/json': { schema: success } } },
          401: { description: 'Not authenticated', content: { 'application/json': { schema: error } } },
        },
      },
    },
    '/api/devices/{id}': {
      delete: {
        tags: ['Devices'],
        summary: "End one device's session",
        security: [{ sessionCookie: [] }],
        parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }],
        responses: {
          200: { description: 'Session ended', content: { 'application/json': { schema: success } } },
          401: { description: 'Not authenticated', content: { 'application/json': { schema: error } } },
          404: { description: 'Device not found', content: { 'application/json': { schema: error } } },
        },
      },
    },
    '/api/plans': {
      get: {
        tags: ['Plans'],
        summary: "The plans and the current account's plan",
        security: [{ sessionCookie: [] }],
        responses: {
          200: { description: 'Plans', content: { 'application/json': { schema: { $ref: '#/components/schemas/PlansOverview' } } } },
          401: { description: 'Not authenticated', content: { 'application/json': { schema: error } } },
        },
      },
    },
    '/api/plans/sync': {
      post: {
        tags: ['Plans'],
        summary: 'Update the plan from Adapty',
        description: [
          'Asks Adapty (server-side API, `ADAPTY_SECRET_API_KEY`) for the',
          "account's active access levels and stores the highest one as the",
          'plan. The app calls it after a purchase or a restore; the phone never',
          'sets its own plan.',
        ].join('\n'),
        security: [{ sessionCookie: [] }],
        responses: {
          200: { description: 'Plan updated', content: { 'application/json': { schema: { $ref: '#/components/schemas/PlansOverview' } } } },
          401: { description: 'Not authenticated', content: { 'application/json': { schema: error } } },
          502: { description: 'Adapty could not be reached', content: { 'application/json': { schema: error } } },
          503: { description: 'Adapty is not configured on this server', content: { 'application/json': { schema: error } } },
        },
      },
    },
    '/api/adapty/webhook': {
      post: {
        tags: ['Plans'],
        summary: 'Adapty webhook',
        description: [
          'Configured in the Adapty dashboard with an `Authorization` header',
          'equal to `ADAPTY_WEBHOOK_AUTH`. Every event is stored in',
          '`subscription_events`; events of a known AllDocs user',
          '(`customer_user_id` = user id) update its plan. An empty body is',
          'answered with 200 (Adapty\'s URL check).',
        ].join('\n'),
        requestBody: { content: { 'application/json': { schema: { type: 'object' } } } },
        responses: {
          200: { description: 'Received', content: { 'application/json': { schema: { type: 'object' } } } },
          401: { description: 'Wrong or missing Authorization header', content: { 'application/json': { schema: error } } },
          500: { description: 'Processing failed (Adapty retries)', content: { 'application/json': { schema: error } } },
        },
      },
    },
    '/api/plans/debug': {
      post: {
        tags: ['Plans'],
        summary: 'Testers only: pick the plan by hand (debug builds of the app)',
        description: [
          'Allowed on a non-production server, or for the emails in PLAN_SWITCH_EMAILS',
          '(403 notAllowed otherwise). A hand-picked plan has no expiry and syncing from',
          'the store leaves it alone; planId null goes back to what the store says. A',
          'real purchase (Adapty webhook) replaces it.',
        ].join('\n'),
        security: [{ sessionCookie: [] }],
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: {
                type: 'object',
                properties: {
                  planId: { type: 'string', enum: ['free', 'premium', 'pro'], nullable: true },
                },
              },
            },
          },
        },
        responses: {
          200: { description: 'Same as GET /api/plans, with pickedByHand' },
          403: { description: 'Not allowed for this account', content: { 'application/json': { schema: error } } },
        },
      },
    },
    '/api/assistant/usage': {
      get: {
        tags: ['Assistant'],
        summary: "This month's assistant requests and allowance",
        security: [{ sessionCookie: [] }],
        responses: {
          200: {
            description: 'Usage',
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  properties: {
                    used: { type: 'integer' },
                    limit: { type: 'integer' },
                    month: { type: 'string', example: '2026-10' },
                  },
                },
              },
            },
          },
        },
      },
    },
    '/api/assistant/ask': {
      post: {
        tags: ['Assistant'],
        summary: 'Answer a question from a few documents',
        description: [
          'The app picks the documents that match the question on the phone and',
          'sends only their text (at most 6 documents, 24,000 characters each,',
          '80,000 in total). Only the monthly request count is stored.',
          'Errors: 403 not on Vault, 429 allowance used up, 413 too much text,',
          '422 the model declined, 502/503 the assistant is unavailable.',
        ].join('\n'),
        security: [{ sessionCookie: [] }],
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: {
                type: 'object',
                required: ['question', 'documents'],
                properties: {
                  question: { type: 'string', example: 'Quando expira o seguro do carro?' },
                  language: { type: 'string', enum: ['pt', 'en', 'es', 'fr'] },
                  documents: {
                    type: 'array',
                    items: {
                      type: 'object',
                      required: ['id', 'text'],
                      properties: {
                        id: { type: 'string' },
                        title: { type: 'string' },
                        text: { type: 'string' },
                      },
                    },
                  },
                },
              },
            },
          },
        },
        responses: {
          200: {
            description: 'Answer',
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  properties: {
                    answer: { type: 'string' },
                    source_ids: { type: 'array', items: { type: 'string' } },
                    found: { type: 'boolean' },
                  },
                },
              },
            },
          },
        },
      },
    },
    '/api/assistant/extract': {
      post: {
        tags: ['Assistant'],
        summary: "A document's details (type, title, tags, holder, dates, NIF, IBAN, policy, amount)",
        security: [{ sessionCookie: [] }],
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: {
                type: 'object',
                required: ['document'],
                properties: {
                  language: { type: 'string', enum: ['pt', 'en', 'es', 'fr'] },
                  document: {
                    type: 'object',
                    required: ['id', 'text'],
                    properties: { id: { type: 'string' }, title: { type: 'string' }, text: { type: 'string' } },
                  },
                },
              },
            },
          },
        },
        responses: { 200: { description: 'Fields; null where the document does not say' } },
      },
    },
    '/api/assistant/summarize': {
      post: {
        tags: ['Assistant'],
        summary: 'A contract in plain words: summary, key points, what to watch out for, dates',
        security: [{ sessionCookie: [] }],
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: {
                type: 'object',
                required: ['document'],
                properties: {
                  language: { type: 'string', enum: ['pt', 'en', 'es', 'fr'] },
                  document: {
                    type: 'object',
                    required: ['id', 'text'],
                    properties: { id: { type: 'string' }, title: { type: 'string' }, text: { type: 'string' } },
                  },
                },
              },
            },
          },
        },
        responses: { 200: { description: 'Summary' } },
      },
    },
    '/api/requests': {
      get: {
        tags: ['Requests'],
        summary: "The user's document requests and the files sent to them",
        security: [{ sessionCookie: [] }],
        responses: {
          200: {
            description: 'Requests, newest first',
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  properties: {
                    requests: {
                      type: 'array',
                      items: {
                        type: 'object',
                        properties: {
                          id: { type: 'string', format: 'uuid' },
                          title: { type: 'string' },
                          message: { type: 'string', nullable: true },
                          albumId: { type: 'string', nullable: true },
                          status: { type: 'string', enum: ['open', 'expired', 'closed'] },
                          createdAt: { type: 'string', format: 'date-time' },
                          expiresAt: { type: 'string', format: 'date-time' },
                          files: {
                            type: 'array',
                            items: {
                              type: 'object',
                              properties: {
                                id: { type: 'string', format: 'uuid' },
                                name: { type: 'string' },
                                contentType: { type: 'string', nullable: true },
                                sizeBytes: { type: 'integer' },
                                uploadedAt: { type: 'string', format: 'date-time' },
                                receivedAt: {
                                  type: 'string',
                                  format: 'date-time',
                                  nullable: true,
                                  description: 'Set once the app collected it; the server copy is then deleted',
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
      post: {
        tags: ['Requests'],
        summary: 'Create a request and get the link to share',
        description: [
          'Vault only (403 otherwise). The link is returned once: only a hash of',
          'its token is stored. Anyone with the link can send up to 10 files',
          '(25 MB each, 100 MB in total) until it expires or is closed.',
        ].join('\n'),
        security: [{ sessionCookie: [] }],
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: {
                type: 'object',
                required: ['title'],
                properties: {
                  title: { type: 'string', example: 'Declaração de IRS 2025' },
                  message: { type: 'string', nullable: true },
                  days: { type: 'integer', minimum: 1, maximum: 30, default: 7 },
                  albumId: { type: 'string', nullable: true, description: 'Album in the app where the files go' },
                  language: { type: 'string', enum: ['pt', 'en', 'es', 'fr'], description: 'Language of the upload page' },
                },
              },
            },
          },
        },
        responses: {
          200: {
            description: 'Created',
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  properties: {
                    id: { type: 'string', format: 'uuid' },
                    url: { type: 'string', example: 'https://all-docs-backend.triplanai.eupasoft.com/r/abc123' },
                    expiresAt: { type: 'string', format: 'date-time' },
                  },
                },
              },
            },
          },
          403: { description: 'Not on the Vault plan', content: { 'application/json': { schema: error } } },
        },
      },
    },
    '/api/requests/{id}/close': {
      post: {
        tags: ['Requests'],
        summary: 'Stop accepting files through the link',
        security: [{ sessionCookie: [] }],
        parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }],
        responses: { 200: { description: 'Closed' }, 404: { description: 'Not found' } },
      },
    },
    '/api/requests/{id}': {
      delete: {
        tags: ['Requests'],
        summary: 'Delete a request and any files still on the server',
        security: [{ sessionCookie: [] }],
        parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }],
        responses: { 200: { description: 'Deleted' }, 404: { description: 'Not found' } },
      },
    },
    '/api/requests/{id}/files/{fileId}': {
      get: {
        tags: ['Requests'],
        summary: 'Download a file that was sent (decrypted)',
        security: [{ sessionCookie: [] }],
        parameters: [
          { name: 'id', in: 'path', required: true, schema: { type: 'string' } },
          { name: 'fileId', in: 'path', required: true, schema: { type: 'string' } },
        ],
        responses: {
          200: { description: 'The file', content: { 'application/octet-stream': { schema: { type: 'string', format: 'binary' } } } },
          404: { description: 'Not found' },
          410: { description: 'Already collected (deleted from the server)' },
        },
      },
    },
    '/api/requests/{id}/files/{fileId}/received': {
      post: {
        tags: ['Requests'],
        summary: 'The app has the file: delete the server copy',
        security: [{ sessionCookie: [] }],
        parameters: [
          { name: 'id', in: 'path', required: true, schema: { type: 'string' } },
          { name: 'fileId', in: 'path', required: true, schema: { type: 'string' } },
        ],
        responses: { 200: { description: 'Marked as received' }, 404: { description: 'Not found' } },
      },
    },
    '/r/{token}': {
      get: {
        tags: ['Requests'],
        summary: 'Public upload page for the person asked (HTML)',
        parameters: [
          { name: 'token', in: 'path', required: true, schema: { type: 'string' } },
        ],
        responses: {
          200: { description: 'Upload page', content: { 'text/html': {} } },
          404: { description: 'Link invalid, expired or closed (HTML page saying so)', content: { 'text/html': {} } },
        },
      },
    },
    '/r/{token}/files': {
      post: {
        tags: ['Requests'],
        summary: 'Send one file (raw body), used by the upload page',
        description: [
          'No account needed: the link token is the permission. The body is the',
          'file itself; it is stored encrypted (AES-256-GCM) until the app collects it,',
          'and deleted after 30 days if it never does. PDF, images, Office and text only.',
          'Error codes: invalid (404), tooBig (413), badType (415), tooMany (429), failed (400).',
        ].join('\n'),
        parameters: [
          { name: 'token', in: 'path', required: true, schema: { type: 'string' } },
          { name: 'name', in: 'query', required: true, schema: { type: 'string', example: 'recibo.pdf' } },
        ],
        requestBody: {
          required: true,
          content: { 'application/octet-stream': { schema: { type: 'string', format: 'binary' } } },
        },
        responses: {
          200: {
            description: 'Received',
            content: { 'application/json': { schema: { type: 'object', properties: { success: { type: 'boolean' } } } } },
          },
          413: { description: 'File too large', content: { 'application/json': { schema: error } } },
        },
      },
    },
    '/api/shares': {
      get: {
        tags: ['Shares'],
        summary: "The user's secure links",
        security: [{ sessionCookie: [] }],
        responses: {
          200: {
            description: 'Shares, newest first',
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  properties: {
                    shares: {
                      type: 'array',
                      items: {
                        type: 'object',
                        properties: {
                          id: { type: 'string', format: 'uuid' },
                          title: { type: 'string' },
                          fileName: { type: 'string' },
                          sizeBytes: { type: 'integer' },
                          hasCode: { type: 'boolean' },
                          maxViews: { type: 'integer', nullable: true },
                          viewCount: { type: 'integer' },
                          lastViewedAt: { type: 'string', format: 'date-time', nullable: true },
                          createdAt: { type: 'string', format: 'date-time' },
                          expiresAt: { type: 'string', format: 'date-time' },
                          status: { type: 'string', enum: ['active', 'expired', 'revoked', 'locked', 'used'] },
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
      post: {
        tags: ['Shares'],
        summary: 'Share a file behind a new link',
        description: [
          'Vault only (403 otherwise). The body is the file itself (up to 50 MB; PDF,',
          'images, Office, text). Its details go in the X-Share-Meta header as base64url',
          'JSON: {title, fileName, days (1-30), code (4-8 digits, optional), maxViews',
          '(optional), language}. Stored encrypted; deleted once the link stops working.',
          'Only hashes of the link token and of the code are kept, so the link is',
          'returned once. Ten wrong codes lock the link for good.',
        ].join('\n'),
        security: [{ sessionCookie: [] }],
        parameters: [
          { name: 'X-Share-Meta', in: 'header', required: true, schema: { type: 'string' } },
        ],
        requestBody: {
          required: true,
          content: { 'application/octet-stream': { schema: { type: 'string', format: 'binary' } } },
        },
        responses: {
          200: {
            description: 'Created',
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  properties: {
                    id: { type: 'string', format: 'uuid' },
                    url: { type: 'string', example: 'https://requests.eupasoft.com/s/abc123' },
                    expiresAt: { type: 'string', format: 'date-time' },
                  },
                },
              },
            },
          },
          403: { description: 'Not on the Vault plan', content: { 'application/json': { schema: error } } },
          413: { description: 'File too large', content: { 'application/json': { schema: error } } },
          415: { description: 'File type not accepted', content: { 'application/json': { schema: error } } },
        },
      },
    },
    '/api/shares/{id}/revoke': {
      post: {
        tags: ['Shares'],
        summary: 'Stop the link now (the file is deleted)',
        security: [{ sessionCookie: [] }],
        parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }],
        responses: { 200: { description: 'Revoked' }, 404: { description: 'Not found' } },
      },
    },
    '/api/shares/{id}': {
      delete: {
        tags: ['Shares'],
        summary: 'Delete a share (and its file, if still there)',
        security: [{ sessionCookie: [] }],
        parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }],
        responses: { 200: { description: 'Deleted' }, 404: { description: 'Not found' } },
      },
    },
    '/s/{token}': {
      get: {
        tags: ['Shares'],
        summary: 'Public page of a secure link (HTML)',
        parameters: [{ name: 'token', in: 'path', required: true, schema: { type: 'string' } }],
        responses: {
          200: { description: 'Who shared what, until when; a form to open or download it', content: { 'text/html': {} } },
          404: { description: 'Expired, revoked, used up or unknown (HTML page saying so)', content: { 'text/html': {} } },
        },
      },
    },
    '/s/{token}/file': {
      post: {
        tags: ['Shares'],
        summary: "The page's form: opens (inline) or downloads the file",
        description: 'Counts a view. A wrong code answers the page again (403) with the attempts left.',
        parameters: [{ name: 'token', in: 'path', required: true, schema: { type: 'string' } }],
        requestBody: {
          content: {
            'application/x-www-form-urlencoded': {
              schema: {
                type: 'object',
                properties: {
                  code: { type: 'string' },
                  mode: { type: 'string', enum: ['open', 'download'] },
                },
              },
            },
          },
        },
        responses: {
          200: { description: 'The file', content: { 'application/octet-stream': { schema: { type: 'string', format: 'binary' } } } },
          403: { description: 'Wrong code or locked (HTML page)' },
          404: { description: 'Not available (HTML page)' },
        },
      },
    },
    '/api/sync': {
      get: {
        tags: ['Sync'],
        summary: "The account's sync: on or off, its devices, the plan's device limit",
        security: [{ sessionCookie: [] }],
        responses: { 200: { description: '{enabled, keyCheck, maxDevices, devices[]}' } },
      },
    },
    '/api/sync/devices': {
      post: {
        tags: ['Sync'],
        summary: 'Add this phone to sync',
        description: [
          'The first device starts the sync and sets keyCheck (HMAC of a fixed text',
          'under the key, which the server never sees). Next ones need a pairingCode',
          'from a device already in (shown in its QR code) and the same keyCheck.',
          'Errors (409): needsPairing, badCode, wrongKey, tooMany (plan device limit).',
        ].join('\n'),
        security: [{ sessionCookie: [] }],
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: {
                type: 'object',
                required: ['keyCheck'],
                properties: {
                  name: { type: 'string', example: 'iPhone 15' },
                  platform: { type: 'string', enum: ['ios', 'android'] },
                  keyCheck: { type: 'string', description: '64 hex characters' },
                  pairingCode: { type: 'string' },
                },
              },
            },
          },
        },
        responses: { 200: { description: '{deviceId, first}' } },
      },
    },
    '/api/sync/devices/{id}': {
      delete: {
        tags: ['Sync'],
        summary: 'Take a device out of sync (the last one out turns sync off and deletes everything)',
        security: [{ sessionCookie: [] }],
        parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }],
        responses: { 200: { description: 'Removed' }, 404: { description: 'Not found' } },
      },
    },
    '/api/sync/pairings': {
      post: {
        tags: ['Sync'],
        summary: 'A one-time code (10 minutes) for the QR that brings in another device',
        security: [{ sessionCookie: [] }],
        parameters: [{ name: 'X-Sync-Device', in: 'header', required: true, schema: { type: 'string' } }],
        responses: { 200: { description: '{code, expiresAt}' } },
      },
    },
    '/api/sync/pairings/status': {
      post: {
        tags: ['Sync'],
        summary: 'Whether a device joined with a code yet',
        security: [{ sessionCookie: [] }],
        responses: { 200: { description: '{joined, deviceName, expired}' } },
      },
    },
    '/api/sync/changes': {
      get: {
        tags: ['Sync'],
        summary: "Other devices' encrypted change batches after a sequence number",
        description: [
          'Also acknowledges everything up to `after`, and says what the device should',
          'do next: requestedBlobs (files others asked for), snapshotFor (devices',
          'waiting for the library), needsSnapshot / snapshotReady (for itself).',
        ].join('\n'),
        security: [{ sessionCookie: [] }],
        parameters: [
          { name: 'X-Sync-Device', in: 'header', required: true, schema: { type: 'string' } },
          { name: 'after', in: 'query', schema: { type: 'integer' } },
        ],
        responses: { 200: { description: '{changes[{seq, deviceId, payload(base64)}], hasMore, latest, ...}' } },
      },
      post: {
        tags: ['Sync'],
        summary: 'Add an encrypted batch after `base` (409 behind when another device added one since)',
        security: [{ sessionCookie: [] }],
        parameters: [
          { name: 'X-Sync-Device', in: 'header', required: true, schema: { type: 'string' } },
          { name: 'base', in: 'query', required: true, schema: { type: 'integer' } },
        ],
        requestBody: {
          required: true,
          content: { 'application/octet-stream': { schema: { type: 'string', format: 'binary' } } },
        },
        responses: { 200: { description: '{seq}' }, 409: { description: 'behind: pull first' } },
      },
    },
    '/api/sync/wait': {
      get: {
        tags: ['Sync'],
        summary: 'Long poll: answers as soon as another device has something for this one (max ~25 s)',
        description: [
          'The open app keeps one of these hanging. It answers {changed: true} right away',
          'when there are changes after `after`, or the moment another device pushes',
          'changes, asks for or uploads a file, joins or is removed; {changed: false}',
          'after ~25 s otherwise. A device waiting for the library only wakes when it arrives.',
        ].join('\n'),
        security: [{ sessionCookie: [] }],
        parameters: [
          { name: 'X-Sync-Device', in: 'header', required: true, schema: { type: 'string' } },
          { name: 'after', in: 'query', schema: { type: 'integer' } },
        ],
        responses: { 200: { description: '{changed}' } },
      },
    },
    '/api/sync/blobs/{blobId}': {
      put: {
        tags: ['Sync'],
        summary: 'Upload an encrypted document file (streamed, up to 1 GB)',
        description: '`for=all`: every other device needs it; otherwise only the devices that asked. 507 quota when too much is waiting.',
        security: [{ sessionCookie: [] }],
        parameters: [
          { name: 'X-Sync-Device', in: 'header', required: true, schema: { type: 'string' } },
          { name: 'blobId', in: 'path', required: true, schema: { type: 'string' } },
          { name: 'for', in: 'query', schema: { type: 'string', enum: ['all'] } },
        ],
        requestBody: {
          required: true,
          content: { 'application/octet-stream': { schema: { type: 'string', format: 'binary' } } },
        },
        responses: { 200: { description: 'Stored' } },
      },
      get: {
        tags: ['Sync'],
        summary: 'Download an encrypted document file',
        security: [{ sessionCookie: [] }],
        parameters: [
          { name: 'X-Sync-Device', in: 'header', required: true, schema: { type: 'string' } },
          { name: 'blobId', in: 'path', required: true, schema: { type: 'string' } },
        ],
        responses: { 200: { description: 'The file' }, 404: { description: 'Not on the server' } },
      },
    },
    '/api/sync/blobs/{blobId}/ack': {
      post: {
        tags: ['Sync'],
        summary: 'This device has the file (deleted once no device needs it)',
        security: [{ sessionCookie: [] }],
        parameters: [{ name: 'blobId', in: 'path', required: true, schema: { type: 'string' } }],
        responses: { 200: { description: 'OK' } },
      },
    },
    '/api/sync/blobs/requests': {
      post: {
        tags: ['Sync'],
        summary: 'Files this device is missing: marks the ones on the server, asks the others for the rest',
        security: [{ sessionCookie: [] }],
        responses: { 200: { description: '{available[]}' } },
      },
    },
    '/api/sync/blobs/existing': {
      post: {
        tags: ['Sync'],
        summary: 'Which of these files are already on the server',
        security: [{ sessionCookie: [] }],
        responses: { 200: { description: '{existing[]}' } },
      },
    },
    '/api/sync/snapshots/{deviceId}': {
      put: {
        tags: ['Sync'],
        summary: "Send the whole library's encrypted state to a device that joined",
        security: [{ sessionCookie: [] }],
        parameters: [
          { name: 'deviceId', in: 'path', required: true, schema: { type: 'string' } },
          { name: 'upto', in: 'query', required: true, schema: { type: 'integer' } },
        ],
        responses: { 200: { description: 'Stored' } },
      },
    },
    '/api/sync/snapshot': {
      get: {
        tags: ['Sync'],
        summary: 'The snapshot sent for this device (X-Upto-Seq: the change it goes up to)',
        security: [{ sessionCookie: [] }],
        responses: { 200: { description: 'Encrypted snapshot' }, 404: { description: 'Not ready' } },
      },
    },
    '/api/sync/snapshot/ack': {
      post: {
        tags: ['Sync'],
        summary: 'Snapshot loaded: carry on from its sequence number',
        security: [{ sessionCookie: [] }],
        responses: { 200: { description: 'OK' } },
      },
    },
    '/api/security/hidden-pin-reset': {
      get: {
        tags: ['Auth'],
        summary: "Where the hidden albums' PIN reset is: none, codeSent, waiting or ready",
        security: [{ sessionCookie: [] }],
        responses: { 200: { description: '{state, codeExpiresAt?, attemptsLeft?, readyAt?, cancelled}' } },
      },
    },
    '/api/security/hidden-pin-reset/request': {
      post: {
        tags: ['Auth'],
        summary: "Email a 6-digit code to reset the hidden albums' PIN (15 min, 5 per day)",
        security: [{ sessionCookie: [] }],
        responses: { 200: { description: 'Status' }, 429: { description: 'tooManyRequests' } },
      },
    },
    '/api/security/hidden-pin-reset/verify': {
      post: {
        tags: ['Auth'],
        summary: 'Confirm the code: the 24 h wait starts and a warning email with a cancel link goes out',
        security: [{ sessionCookie: [] }],
        responses: {
          200: { description: 'Status (waiting)' },
          400: { description: 'wrongCode (attemptsLeft)' },
          410: { description: 'expired' },
          429: { description: 'tooManyAttempts' },
        },
      },
    },
    '/api/security/hidden-pin-reset/complete': {
      post: {
        tags: ['Auth'],
        summary: 'The wait is over: the app may set the new PIN (single use; 409 notReady before)',
        security: [{ sessionCookie: [] }],
        responses: { 200: { description: 'OK' }, 409: { description: 'notReady' } },
      },
    },
    '/api/security/hidden-pin-reset/cancel': {
      post: {
        tags: ['Auth'],
        summary: 'Cancel the reset from the app',
        security: [{ sessionCookie: [] }],
        responses: { 200: { description: 'OK' } },
      },
    },
    '/api/config/cloud': {
      get: {
        tags: ['Config'],
        summary: 'OAuth client ids for Google and Dropbox',
        description: [
          'Public (needed before sign-in). Values come from the server .env;',
          '`null` means that provider is not configured and the app shows it',
          'as "coming soon". These are public PKCE client ids, not secrets.',
        ].join('\n'),
        responses: {
          200: {
            description: 'Client ids',
            content: { 'application/json': { schema: { $ref: '#/components/schemas/CloudConfig' } } },
          },
        },
      },
    },
  },
}
