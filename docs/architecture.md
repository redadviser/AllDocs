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
