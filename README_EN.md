# Vellum

Chinese_version:[README.md](README.md)

A local-first ebook app built around reading: a quiet digital study. Cupertino-first. Your data stays on the device.

---

## User Guide

### Library

- Import **EPUB / MOBI / TXT**
- **Three-column grid** shelf with **search** (title / cover text / format)
- **Custom folders**: create, rename, delete; long-press a book to move it in/out
- **Long-press to edit the cover**: upload an image, or generate a text cover
- Index and body are stored separately; startup only loads the light index

### Reading

- **Scroll** or **paged** reading
- Page-turn styles: cover / slide / none; tap left/right to turn, tap the middle for controls
- Draggable progress; jump via table of contents, bookmarks, and **highlights & notes**
- **Full-text search** in the catalogue panel: two characters start a whole-book scan. Results are
  **grouped by chapter**, each hit shows the matching snippet (query highlighted), the previous
  line as context, paragraph number, and page. Repeated hits in one paragraph are counted. The
  summary bar shows “N paragraphs · M hits” with next/previous step buttons. Tapping a result
  jumps to the passage and **marks the query in the body** (cleared on page turn or scroll).
  Search waits for a typing pause; even very large books (tested at 600k paragraphs) stay smooth.
- Font size, line spacing, weight, **brightness**, **eye care**, paper colour, system / imported TTF
- Rich text: bold, italic, underline, heading levels, quote, centered
- Selection actions: **highlight**, copy, Bing lookup, DeepL translate, note
  (highlights and notes render in the body)
- Footer shows **current chapter + chapter progress + time left**, book progress, and battery
- **Keep screen on**, **volume-key paging** (toggle in reading settings)
- Bookmark from the top bar or by pulling down the page
- Progress and bookmarks save automatically
- Per-chapter progress: chapters without a saved position open at their start; leaving and
  returning restores where you were

### Writing

- Local drafts: create, import (`.md` / `.txt` / `.markdown`), long-press to delete
- **Auto-save while you type** — no save button needed; live **character / word** counts
- Export to a location you choose (Markdown or plain text)
- **Local Markdown preview**: switch the editor to a rendered view (headings, bold, italic, lists,
  quotes, link text) using the same layout pipeline as the reader — offline, no remote images
- **Typography settings are global** (shared by every draft): font (including imported TTFs, same
  picker as the reader), size, weight, novel mode
- **Novel mode** (plain-text drafts): when on, keeps “two-em indent + blank line between
  paragraphs” automatically; Enter opens a new indented paragraph. Inert for Markdown drafts

### Tools & Settings

- **MOBI / EPUB → TXT** converter on its own page, with a save location picker
- Light / dark theme
- Font manager (import / activate / delete)
- **Reading notes import / export**: export as JSON. Import accepts a Vellum JSON backup, or
  Markdown / plain text in the `# Title` + `> highlight` + comment-line shape. Books are matched
  from the export’s book id → title (punctuation-folded `《》`, unique substring match). When the
  match is uncertain it is **never guessed** — pick the book before import, or keep them as
  “unassociated notes” and link them later in Settings.
- **In-app updates**: the Settings → Updates section shows the **current version**; the app can
  check on launch (toggleable), pick an APK by device ABI, download, and hand off to the system
  installer. The update repository is configurable (`owner/repo` or a full URL)
- Storage usage and cleanup

### Not supported yet

- Code blocks in Markdown preview render as plain paragraphs (no monospace / indent)
- DRM-protected ebooks
- KF8 / AZW3 proprietary layout (parsed as classic MOBI7)

---

## Developer Guide

### Layout

```
lib/
  main.dart                 entry
  app.dart                  VellumApp + LibraryShell
  vellum.dart               public exports
  pages/                    home, library, settings, convert-to-txt, cover editor, writing
  reader/                   reader page, pagination, paragraphs, gestures, chrome
  services/                 MOBI/EPUB/HTML parsing, library storage, import, updates
  theme/ util/ widgets/     theme and helpers
```

### Environment

- Flutter stable (Dart SDK `^3.12.2`)
- Android / Windows and other Flutter-supported platforms

### Dependencies (China mirrors)

```bat
tool\pub_get_mirror.bat
```

The script sets `PUB_HOSTED_URL` and `FLUTTER_STORAGE_BASE_URL` for the current session only.
Android Gradle repositories already use Aliyun / Tencent mirrors.

### Common commands

```bat
flutter pub get
flutter analyze
flutter test
flutter run
```

### Build

```bat
flutter build apk --release
flutter build apk --release --split-per-abi
:: or
flutter build appbundle --release
```

Note: release builds currently use the debug keystore for local testing. Configure a release
keystore before store submission.

### Update package naming

In-app updates pick an APK by device ABI. File names must be `Vellum-V<version>-<abi>.apk`:

| File | Target |
|------|--------|
| `Vellum-V1.0.8-arm64-v8a.apk` | Most phones (recommended) |
| `Vellum-V1.0.8-armeabi-v7a.apk` | Older 32-bit devices |
| `Vellum-V1.0.8-x86_64.apk` | x86 tablets / emulators |
| `Vellum-V1.0.8-universal.apk` | Fallback when ABI is unknown |

The app reads `SUPPORTED_ABIS`, ranks the matching package first, and labels it “recommended”.
A wrong ABI fails at install time with “App not installed”.

The version source of truth is `pubspec.yaml` `version` — the same string shown as
**Current version** in Settings.

### CI / Release

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `.github/workflows/build.yml` | manual | test + build APK/AAB |
| `.github/workflows/release.yml` | manual or `v*` tag | tag, per-ABI APKs, GitHub Release |

Release produces 3 ABI-split APKs (`--split-per-abi`) plus one universal package, renamed to the
table above.

Manual release: **Actions → Release → Run workflow** (tag defaults to `pubspec.yaml` `version`).

Push a tag:

```bat
git tag v1.0.8
git push origin v1.0.8
```

## License

See [LICENSE](LICENSE).
