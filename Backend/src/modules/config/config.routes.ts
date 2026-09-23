import { Router } from 'express'

export const configRouter = Router()

// OAuth client ids the app needs to connect to Google (sign-in + Drive),
// OneDrive and Dropbox. They're public identifiers (mobile apps use PKCE,
// no client secret), so this is deliberately unauthenticated: the app needs
// the Google ids before anyone has signed in. Keeping them here means a key
// can be added or rotated without shipping a new app build.
//
// Users' own cloud tokens never come through this server — they stay in
// the phone's keystore.
configRouter.get('/cloud', (_req, res) => {
  const value = (name: string) => process.env[name]?.trim() || null
  res.set('Cache-Control', 'public, max-age=3600')
  res.json({
    google: {
      webClientId: value('GOOGLE_SIGNIN_WEB_CLIENT_ID'),
      iosClientId: value('GOOGLE_SIGNIN_IOS_CLIENT_ID'),
    },
    oneDrive: { clientId: value('ONEDRIVE_CLIENT_ID') },
    dropbox: { appKey: value('DROPBOX_APP_KEY') },
  })
})
