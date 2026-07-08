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
