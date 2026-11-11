# OpenLeaf 3.0 changelog

## Explore reliability
- Limit catalog traffic to three concurrent requests to reduce request bursts and timeout cascades.
- Retry transient network errors, timeouts, HTTP 429, and server errors once.
- Use a 12-second timeout per request attempt.
- Preserve a previously successful feed if its refresh fails.
- Keep category shelves independent and show a compact retry state instead of a large failure panel.
- Show a clear empty state when a genre has no downloadable EPUB books.

## Author discovery
- Normalize author names across comma-formatted and standard name formats.
- Filter remote search results to the exact author rather than showing unrelated title matches.
- Exclude the book currently being viewed and deduplicate by Gutenberg ID.
- Continue to show cached recommendations while a refresh is in progress or fails.

## Reading experience
- Add a compact reading-progress indicator to the EPUB reading screen.
- Improve the visual treatment of the reader settings control.
- Remove the floating Logman debug button from the main app UI.

## Verification
- Added author-name normalization regression tests.
- Flutter/Dart CLI was not available in the editing environment, so a fresh Android build and full test run still need to be performed locally.
