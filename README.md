# AllDocs

AllDocs is a local-first mobile app for organizing documents on a phone.

## Current Recommendation

For the first version, a backend is not worth the complexity. Document organization is naturally local: the files already live on the device, the app must work offline, and users will expect privacy around contracts, invoices, IDs, insurance papers, and scans.

Use local storage first:

- Flutter app in `ui/`
- local document metadata store, later backed by SQLite/Drift
- device/cloud import integrations handled by mobile plugins
- optional encrypted backup/export for portability

Add a TypeScript backend with PostgreSQL only when the product needs account sync across devices, web access, shared folders, server OCR/classification, subscription state, or a central encrypted backup catalog. PostgreSQL should live behind the server; it is not the right database to run inside the mobile app.

## Implemented Skeleton

- `Docshelf`: real shelves and document albums, with create shelf/create album/import into album flows
- `Arquivo`: imports files from the phone, keeps an unorganized queue, and archives documents into albums
- `Perfil`: account card, real local storage usage, stats, cloud/backup/security/premium settings, color/font/contrast customization
- `lib/models`: document, category, folder, profile, storage models
- `lib/services`: local-first service/store boundary persisting metadata as JSON and copied files in app storage
- `lib/theme` and `lib/common`: shared visual system in the AllPhotos-style dark blue interface

The current functional store is intentionally simple JSON so the frontend can move quickly. The natural next step is replacing it with SQLite/Drift while keeping the same `DocumentsService` surface.

## Run

```bash
cd ui
flutter run
```

## Verify

```bash
cd ui
flutter analyze
flutter test
```
