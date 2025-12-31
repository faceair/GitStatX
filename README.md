# GitStatX

GitStatX is a macOS app built with SwiftUI for generating offline, visual Git statistics reports. It parses commit history and file diffs via native Git commands, aggregates metadata into SwiftData, and writes an HTML report you can export as a folder.

![](image.png)

## Features
- Manage multiple repositories or folders in a sidebar
- Incremental stats with cache (`stats_cache.json`) to skip unchanged commits
- Progress tracking for scanning and processing stages
- Offline HTML report with bundled template and Chart.js assets
- SwiftData persistence for authors, commits, and files
- Export the generated report directory as a folder

## Stats Coverage
- Summary: total commits/authors/files, current LOC snapshot, total added/removed lines, repo age/active days, averages per day/author
- Time: daily/weekly/monthly/yearly commit counts, last-32-weeks trend, hour/day/hour-of-week heatmaps, timezone breakdown, activity period range
- Lines & files: cumulative LOC over time, yearly/monthly added vs. removed lines, file-count growth by date
- Authors: per-author commits/add/remove, first/last commit dates, active days, email domain split, top authors plus month/year leaders
- Files & content: per-file commit/add/remove stats, extensions with file counts/LOC/size snapshot, total and average file size
- Tags: tag timeline with commit counts, author counts, days between tags
- Details: full commit list (hash/author/date/message) for reference

## Requirements
- macOS 14+
- Xcode 15+ or Swift 5.9+
- Git available in PATH (default `/usr/bin/git`)

## Quick Start
1. Run from the repo root:
   ```bash
   swift run GitStatX
   ```
   Or open in Xcode and run the executable target `GitStatX`.
2. In the toolbar, click **Add**:
   - **Add Repository** to pick a folder containing `.git`
   - **Add Folder** to create a grouping node
3. Selecting a repository triggers stats generation automatically; if not, use **Generate Statistics** on the report page.
4. After generation, export the report via the **Export** button (saves the full report directory).

## Packaging
- Run `./build.sh` to produce a release `.app` at `dist/GitStatX.app`.
- GitHub Actions workflow `.github/workflows/ci.yml` runs `swift test` on `macos-latest`, then calls the same script and uploads the app bundle artifact.
- App icon assets (`AppIcon.svg`, `AppIcon.iconset`, `AppIcon.icns`) are kept in `Sources/GitStatX/Resources/`; `build.sh` copies the `.icns` directly (falls back to generating from the SVG if missing).

## Directories & Storage
- Reports and cache: `~/Library/Application Support/GitStatX/Reports/<project-id>/`
- SwiftData store: `~/Library/Application Support/GitStatX/default.store`
- Templates/assets: `Sources/GitStatX/Resources/templates`, `Sources/GitStatX/Resources/Chart.js`

## Testing
Run all tests:
```bash
swift test
```
Performance-oriented tests create large reports in temporary directories; SQLite warnings about missing files may appear during teardown but the suite completes.
