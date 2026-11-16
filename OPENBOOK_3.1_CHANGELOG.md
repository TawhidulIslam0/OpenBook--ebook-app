# OpenBook 3.1 — Reliability & Reader Fixes

## Fixed
- SharedPreferences now initializes and completes before `runApp`, removing a first-launch race that could leave the initial UI incomplete until a restart.
- Explore no longer fires every genre request at once. Each visible shelf loads independently, reducing request bursts and freeing catalog capacity for author lookups.
- Catalog requests use shorter bounded timeouts and do not retry slow connection timeouts; only explicit transient server/rate-limit responses receive one retry.
- Genre pagination replaces the `page` query parameter through `Uri`, avoiding malformed or duplicated page parameters.
- More-from-author lookups benefit from the removal of the Explore prefetch request storm; exact author matching and cached fallback remain in place.
- Opening an online book now uses a validated temporary EPUB file. It does not create a permanent offline download. The temporary file is removed when the reader closes.
- Explicit Download continues to use persistent app storage for offline reading.
- EPUB progress is now calculated across the complete publication using the sum of pagination counts for all spine items, rather than only the current chapter. The saved locator and progress are restored when reopening the book.
- Landscape orientation is applied only after the reader settings dialog closes, preventing the dialog from rotating sideways while open.
- Removed Logman navigation/provider observers from the normal app launch so the debugging overlay does not appear in the reading experience.

## Validation
- Added tests for SharedPreferences initialization and temporary-download URL validation.
- Flutter/Dart SDK was not available in the editing environment; run `flutter pub get`, `flutter test`, `flutter analyze`, and `flutter run` locally before treating the build as verified.
