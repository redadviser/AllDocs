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

## When Backend Becomes Worth It

Add a backend once one of these becomes a product requirement:

- sign-in and subscription state shared across devices
- cloud sync between multiple phones/tablets/web
- shared document spaces
- server-side OCR, classification, duplicate detection, or search indexing
- encrypted backup catalog with restore across new devices

Suggested backend shape then:

```text
server/
  src/
    modules/
      documents/
        controller.ts
        service.ts
        index.ts
      categories/
        controller.ts
        service.ts
        index.ts
      sync/
        controller.ts
        service.ts
        index.ts
      users/
        controller.ts
        service.ts
        index.ts
    models/
      document.ts
      category.ts
      user.ts
    database/
      postgres.ts
```

The mobile app should still cache locally even after a backend exists.

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
