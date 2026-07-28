# AllDocs Architecture Notes

## Local-first MVP

The viable first architecture is a Flutter app with a local metadata database and files kept on device storage. This keeps document viewing, categorization, favorites, shelves, albums, and recent imports fast and usable offline.

The current implementation uses a JSON state file through `DocumentsService`/`LocalDocumentsStore` while the frontend takes shape. That keeps the service boundary similar to AllPhotos and makes it easy to migrate the internals to SQLite/Drift without rewriting screens.

Recommended local stack for the next implementation step:

- `drift` or `sqflite` for document metadata
- device file picker for imports
- camera/document scanner plugin for scans
- OS biometric APIs for app lock
- Google Drive/OneDrive/iCloud integrations only as optional import/backup providers

## Backend (Phase 1: accounts)

`Backend/` is an Express + TypeScript service, deliberately built as a
sibling of `AllPhotos/Backend` rather than reinvented: same module layout
(`src/modules/<name>/{<name>.routes,controller,service}.ts`), same
`src/lib/db.ts` + `src/lib/auth.ts` shape, same CapRover deployment
(`Dockerfile` + `captain-definition`), same local dev loop (`docker-compose`
Postgres + `scripts/schema.sql` + `tsx watch`). This isn't NestJS, and it
isn't S3/RevenueCat/Railway — it mirrors whatever AllPhotos already runs in
production, since the two apps are the same "All\*" family and should not
diverge in backend stack for no reason.

**Shared accounts, separate app data.** AllPhotos and AllDocs are both
"All\*" apps from the same suite, so a user's login (email + password) is
shared between them: AllDocs' backend authenticates against AllPhotos'
existing `users` table rather than creating its own. Concretely:

- `ACCOUNTS_POSTGRES_*` env vars point AllDocs' backend at the `allphotos`
  database (same Postgres server as AllDocs' own database in production,
  different database) — read/write access to the `users` table only. AllDocs
  never touches AllPhotos' own domain tables (`profiles`, `albums`, `photos`,
  `shelves`, ...).
- `POSTGRES_*` env vars (same names AllPhotos uses) point at AllDocs' own
  `alldocs` database, holding only AllDocs-specific tables: `devices` this
  phase, later `vaults`/`documents_metadata`/`reminders`/`subscriptions` per
  the product roadmap.
- Each backend issues and verifies its own JWT with its own `JWT_SECRET` —
  there is no cross-app token handoff (a user still logs into each app
  separately on their device), just a shared credential store. Sharing the
  signing secret would add risk (a compromised AllDocs backend could forge
  AllPhotos sessions) for no functional benefit.
- Password hashing (bcrypt, cost 10) matches AllPhotos exactly, so a
  password set in either app validates in both.

This means creating an account in AllDocs can create a *new* shared `users`
row (if the email doesn't exist yet) that AllPhotos could also authenticate
against later, and vice versa — that's the intended behavior, not a bug.

The mobile app should still cache locally even after a backend exists —
Phase 3 of the roadmap (encrypted sync) is what actually starts sending
document data to the server; Phase 1 is accounts only.

### Flutter side (AuthService) — the "AllID" screen

`ui/lib/screens/auth/all_id_screen.dart` is the branded entry screen for the
shared account, called **AllID** (like "Apple ID"/"Google Account" — one
identity across the whole "All\*" suite, extensible to future apps without
renaming anything). It has a login/signup toggle plus a "Continue with
Google" button, replacing the old placeholder `LoginScreen`.
`AuthService` (`ui/lib/services/auth_service.dart`) has real
`login`/`signup`/`loginWithGoogle` call paths, all gated behind
`LocalModeConfig.isLocalOnly` (still `true` by default — flipping it is a
deliberate, separate step once the backend is actually deployed somewhere
reachable). The session token is kept behind an `AuthTokenStore` seam (real
implementation backed by `flutter_secure_storage`, swappable in tests)
rather than `SharedPreferences`, since a real JWT is a more sensitive
artifact than the local-only mock flag it replaces.

**Sign in with Google, and why it logs straight into the shared account.**
Both apps' backends authenticate against the same `users` table (see above),
keyed by email. `POST /api/auth/google/signin` verifies the Google ID token
server-side (`google-auth-library`, never trusting a client-supplied email)
and then does a find-or-create by email against that same shared table: if
`x@gmail.com` already has a password-based account (from either app), Google
sign-in resolves to that exact same account and just logs in — no separate
"Google account" identity is created. A brand-new Google email creates a new
shared `users` row (password_hash set to an unusable random hash, since the
column is `NOT NULL` and this account has no password) that a future
password-based signup with the same email would then also resolve to.

**Setup checklist before AllID's Google button actually works** (none of
this is done yet — this is genuinely new capability, not something
AllPhotos already had for sign-in, only for Drive linking):

1. Create an OAuth consent screen in Google Cloud Console (or reuse
   AllPhotos' project if there is one) and register **three** OAuth clients:
   iOS, Android, and Web (the Web one is used as `serverClientId` so the ID
   token's audience is verifiable server-side).
2. Backend: fill in `GOOGLE_SIGNIN_IOS_CLIENT_ID` /
   `GOOGLE_SIGNIN_ANDROID_CLIENT_ID` / `GOOGLE_SIGNIN_WEB_CLIENT_ID` in
   `Backend/.env` (see `Backend/.env.example`).
3. Flutter: set `GoogleAuthConfig.serverClientId`
   (`ui/lib/services/google_auth_config.dart`) to the Web client ID.
4. Native platform config the `google_sign_in` plugin needs (not yet
   present in this repo): Android's `google-services.json` /
   `applicationId` matching the Android OAuth client's package name and
   SHA-1, and iOS's URL scheme in `Info.plist` matching the iOS OAuth
   client's reversed client ID. See the package's own setup docs — this is
   standard `google_sign_in` platform setup, nothing AllDocs-specific.

Two known gaps, left out deliberately rather than by oversight:

- **No automated test for any of the real network branches** (password or
  Google). `LocalModeConfig.isLocalOnly` is a hardcoded `const`, so a test
  can't flip it to exercise the network path without a larger refactor.
  Password login/signup were verified manually end-to-end against the real
  Backend (see the Backend section above); Google sign-in could only be
  smoke-tested for its error paths (not configured, missing idToken) since
  no real Google Cloud credentials exist yet to test a real token.
- **Not verified in a running app.** This environment has no macOS desktop
  target configured and no attached iOS/Android device reachable for a full
  build; `flutter analyze` is clean and the widget test suite (which taps
  through the AllID screen's login button as part of its flow) passes, but
  nobody has visually looked at the rendered screen yet.

## iOS scanning parity (known gap, accepted for now)

`DocumentScannerService` uses `google_mlkit_document_scanner` on Android (real
edge detection, auto-crop, multi-page capture). On iOS it falls back to a
plain `image_picker` camera shot: no edge detection, no auto-crop, no
multi-page batching. This is a real, currently-accepted gap, not an
oversight — an iOS scanner reads worse than Apple's own free Notes app
(which uses VisionKit).

Researched options to close this later (evaluated 2026-07-28, re-check
maintenance status before committing to one):

- **`flutter_doc_scanner`** — wraps native `VNDocumentCameraViewController`
  (VisionKit) on iOS and ML Kit on Android behind one API
  (`getScanDocumentsUri()` returns page image URIs, compatible with our
  existing OCR/searchable-PDF pipeline). v0.0.21, 162 likes/150 pub points,
  but an unverified pub.dev uploader — worth a second look at adoption/issues
  before depending on it.
- **`cunning_document_scanner`**, **`doclens`**, **`aio_scanner`** — same
  VisionKit-backed approach on iOS, not yet compared in depth.

Decision: deferred. Ship with the `image_picker` fallback for now rather than
add a native dependency from an unverified author without the ability to
test on real iOS hardware in the session that evaluated it. Revisit as part
of the roadmap's Phase 6 (hardening) before a paid iOS launch, testing
candidates on a real device/simulator first.
