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

## On-device classification and expiry reminders (Phase 1: no backend needed)

`DocumentClassifier` (services) runs right after OCR in the scan pipeline
(`DocumentScannerService`) and is pure/rule-based: keyword matching across
pt/en/es/fr yields a `DocumentSemanticType` (invoice, receipt, contract,
identity document, medical, insurance, warranty, other) with a 0-1
confidence, plus a validity/expiry date extracted near a "valid until"-style
phrase for the types where that's meaningful. Nothing currently auto-files
based on this — it's stored on `DocumentFile` and shown as metadata
(`DocumentTile` shows the due date when present), never used to silently
move a document into an album.

`ReminderScheduler` (pure) decides *when* a local notification should fire
(`validityDate - leadTime`, default 14 days) and computes a stable
per-document notification id; `ExpiryReminderService` is the actual
`flutter_local_notifications` integration, called from
`LocalDocumentsStore.scanDocumentWithCamera` (best-effort, never breaks
scanning) and `deleteDocument` (cancels the reminder). This is entirely
on-device — no server involved, unlike the roadmap's later Phase 4
cross-device push, which is a deliberate, disclosed exception to
zero-knowledge sync that this local-only version isn't.

The Docshelf screen shows an "Expiring soon" panel (mirroring the existing
Recent/Favorites panels) whenever `DocumentsSnapshot.expiringDocuments` is
non-empty.

Known limitations, accepted for this first pass:
- Rule-based classification will misfire on formats/languages it wasn't
  built for (a v1 problem the roadmap's Phase 6 addresses with a trained
  on-device model once there's real accept/reject data to train on).
- Date parsing assumes DD/MM/YYYY (matches pt/es/fr; ambiguous for en-US
  MM/DD dates).
- `flutter_local_notifications`/`timezone` are new platform-channel
  dependencies with no automated test coverage of the actual notification
  delivery (the pure decision logic in `ReminderScheduler` is fully tested;
  the plugin integration itself isn't runnable in this environment — no
  device was available to verify a notification actually fires).

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

**Own accounts.** AllDocs has its own accounts, separate from AllPhotos
(sharing one login across the suite was considered and deliberately left
for later, once the apps have scaled). Everything lives in AllDocs'
`alldocs` database (`POSTGRES_*` env vars): `users` (email + bcrypt
password hash), `profiles` (display name, plan, avatar) and `devices`,
later `vaults`/`documents_metadata`/`reminders`/`subscriptions` per the
roadmap. The server creates any missing table on start from
`scripts/schema.sql` (all `IF NOT EXISTS`), so a deploy needs no manual SQL.
Sessions are JWTs signed with AllDocs' own `JWT_SECRET`.

If the suite login comes back later, the path is a shared accounts
database the apps authenticate against (each keeping its own
`JWT_SECRET`), plus merging existing accounts by email.

The mobile app should still cache locally even after a backend exists —
Phase 3 of the roadmap (encrypted sync) is what actually starts sending
document data to the server; Phase 1 is accounts only.

### Flutter side (AuthService) — the account screen

`ui/lib/screens/auth/auth_screen.dart` is the entry screen: a login/signup
toggle plus a "Continue with Google" button. `AuthService`
(`ui/lib/services/auth_service.dart`) has the `login`/`signup`/
`loginWithGoogle` call paths, gated behind `LocalModeConfig.isLocalOnly`.
The session token is kept behind an `AuthTokenStore` seam (real
implementation backed by `flutter_secure_storage`, swappable in tests).

**Sign in with Google.** `POST /api/auth/google/signin` verifies the Google
ID token server-side (`google-auth-library`, never trusting a
client-supplied email) and does a find-or-create by email: if the email
already has a password account, Google sign-in logs into that same account.
A new Google email creates a `users` row with an unusable random password
hash (the column is `NOT NULL`). Setup: see "Cloud integrations" below —
the same Google OAuth clients serve sign-in and Drive.

**First run.** Once signed in, a library with no shelves gets a starter
"Personal" shelf with Contracts and Invoices albums, in the app's language
(`LocalDocumentsStore.ensureStarterShelf`, once per library).

Known gap: no automated test covers the real network branches (password or
Google) — `LocalModeConfig.isLocalOnly` is a hardcoded `const`.

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

## Cloud integrations (Google Drive, OneDrive, Dropbox)

Each provider needs an app registration of our own. The ids live in the
**backend's `.env`** (`GOOGLE_SIGNIN_WEB_CLIENT_ID`,
`GOOGLE_SIGNIN_IOS_CLIENT_ID`, `GOOGLE_SIGNIN_ANDROID_CLIENT_ID`,
`ONEDRIVE_CLIENT_ID`, `DROPBOX_APP_KEY`) and reach the app through the public
`GET /api/config/cloud` (they're public PKCE client ids, not secrets). The
app (`CloudKeys`) fetches them at startup and caches them for offline use, so
adding or rotating a key needs no new build. A provider without its id shows
as "Coming soon" on the Connections page.

Users' cloud tokens never go through the backend: they're issued to the
phone and kept in its keystore (`CloudTokenStore`).

Two things stay build-time:
- iOS: the reversed Google iOS client id must be a URL scheme — copy
  `ui/ios/Flutter/CloudKeys.xcconfig.example` to `CloudKeys.xcconfig`
  (git-ignored) and fill it in.
- Optional dev override: a `--dart-define` of the same name (or
  `--dart-define-from-file=cloud_keys.json`, see
  `ui/cloud_keys.example.json`) wins over the backend's value, e.g. to test
  other registrations.

OAuth redirect for OneDrive and Dropbox: `com.alldocs.app:/oauth2redirect`
(`CloudConfig.redirectUri`, already wired in `build.gradle.kts` and
`Info.plist`).

**Google Drive** (Google Cloud console, same project as "Sign in with Google"):
1. Enable the Google Drive API.
2. OAuth consent screen: add the scopes `drive.readonly` and `drive.appdata`.
   `drive.readonly` is a *restricted* scope — fine for test users while the
   app is in "Testing", but publishing needs Google's verification.
3. Credentials: a **Web** client (→ `GOOGLE_SIGNIN_WEB_CLIENT_ID`), an
   **Android** client for `com.alldocs.app` with the SHA-1 of
   every signing key (debug, upload, Play app signing), and an **iOS**
   client for `com.alldocs.app` (→ `GOOGLE_SIGNIN_IOS_CLIENT_ID`;
   the Android client id → `GOOGLE_SIGNIN_ANDROID_CLIENT_ID`).
4. iOS: put the iOS client's *reversed* id
   (`com.googleusercontent.apps.<...>`) in
   `ui/ios/Flutter/CloudKeys.xcconfig` — `Info.plist` already registers it
   as a URL scheme.

Backups go to Drive's hidden app-data folder (not visible in the Drive UI).

**OneDrive** (Microsoft Entra admin center → App registrations):
1. New registration, "Accounts in any organizational directory and personal
   Microsoft accounts".
2. Authentication → add platform "Mobile and desktop applications" with the
   redirect URI above; allow public client flows.
3. API permissions (Microsoft Graph, delegated): `Files.ReadWrite`,
   `User.Read`, `offline_access`.
4. The Application (client) id → `ONEDRIVE_CLIENT_ID`.

Backups go to `Apps/AllDocs` (the app folder) in the user's OneDrive.

**Dropbox** (dropbox.com/developers/apps):
1. Create app → Scoped access → Full Dropbox (browsing/import needs it).
2. Permissions: `account_info.read`, `files.metadata.read`,
   `files.content.read`, `files.content.write`.
3. OAuth 2 redirect URIs: the redirect URI above.
4. App key → `DROPBOX_APP_KEY` (PKCE, no secret in the app). Until the app
   is approved for production only the developer + up to 500 users can link.

Backups go to `/AllDocs Backups`. Every provider keeps the latest 3 backups
(`BackupService.keptCloudBackups`); older ones are deleted after each upload.
