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
      'Backend of the AllDocs app. Accounts are shared with AllPhotos (same',
      '`users`/`profiles`), everything else lives in AllDocs\' own database.',
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
      '- *Google Drive, OneDrive, Dropbox*: authorized on the phone (PKCE);',
      '  the OAuth redirect is the app\'s own scheme',
      '  `com.eupasoft.alldocs:/oauth2redirect`, and the tokens stay in the',
      '  phone\'s keystore. The backend only hands out the public client ids',
      '  (`GET /api/config/cloud`) and never sees users\' cloud tokens.',
    ].join('\n'),
  },
  servers: [{ url: '/', description: 'This server' }],
  tags: [
    { name: 'Auth', description: 'AllID accounts and sessions' },
    { name: 'Devices', description: 'Signed-in devices (sessions) of the current user' },
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
          oneDrive: {
            type: 'object',
            properties: { clientId: { type: 'string', nullable: true } },
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
        summary: 'Sign in with Google (AllID)',
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
    '/api/config/cloud': {
      get: {
        tags: ['Config'],
        summary: 'OAuth client ids for Google, OneDrive and Dropbox',
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
