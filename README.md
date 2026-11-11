# OpenBook

OpenBook is a Flutter ebook library for discovering public-domain books, reading EPUBs, saving favorites and downloads, and keeping a personal reading shelf.

## Features

- Discover public-domain ebooks through the Gutendex / Project Gutenberg catalog.
- Search by book title, author, and subject, with popularity/title/newest sorting.
- Browse featured books, categories, and recently added titles.
- Read EPUB books using the integrated Iridium reader.
- Search the catalog as you type, with debounced requests and stale-request cancellation.
- Filter catalog search by language, sort results, and page through large result sets.
- Refresh Explore feeds, browse paginated genres, or use Surprise Me for a live catalog pick.
- Save favorites and cache downloaded EPUBs locally for faster offline reopening.
- Track cancellable download progress, retry failures, validate EPUB archives, and manage cached-file storage.
- Import EPUB and PDF files into a persistent local library.
- Organize books into custom collections and Want to Read, Currently Reading, and Finished shelves; save ratings and reviews.
- Use reader bookmarks, highlights, saved reading position, persistent typography/themes, brightness, and landscape settings.
- Read selected text aloud with speech controls.
- Continue reading from the last saved EPUB/PDF position; set daily goals and track streaks, reading time, and page activity.
- Light and dark themes with an editorial forest-green visual identity.

See [FEATURES_AUDIT.md](./FEATURES_AUDIT.md) for implemented and remaining
features. Library data starts empty and remains on device. Downloads can be
removed independently of library history; imported-file removal deletes the
private imported copy.

## Run in VS Code

1. Install Flutter and the Android SDK.
2. Open this folder in VS Code.
3. Run `flutter pub get`.
4. Connect an Android device or start an emulator.
5. Run `flutter run`.

The app uses Project Gutenberg's public-domain catalog via Gutendex. Catalog availability and EPUB formats vary by title. Reading history, imported books, cached EPUBs, reader preferences, and annotations are stored locally on the device. Imported files are copied into app-managed storage; removing an imported book from the library deletes that copy.


## OpenLeaf 3.0 update

This update focuses on reliable catalog discovery and a cleaner reading experience:

- Genre requests are queued with a maximum of three simultaneous catalog requests.
- Catalog requests use a shorter per-attempt timeout and retry transient network/server failures once.
- Previously loaded category data remains available when a refresh fails (stale-while-error).
- Author recommendations now normalize author names and filter search results to the exact author, excluding the current book.
- The EPUB reader shows a compact reading-progress indicator and has a clearer settings control.
- Removed the floating Logman debug overlay from the main app experience.
- Version updated to 3.0.0+20.

Run `flutter pub get`, `flutter test`, `flutter analyze`, and `flutter run` after extracting the project.
