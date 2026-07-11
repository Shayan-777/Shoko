# Shoko

Terminal ebook reader for `.epub`, `.fb2`, `.pdf`, `.mobi`, `.azw`, `.azw3`, and `.rtf` files (see [format support limits](#format-support-limits)).

## Features

- **Library** — scans common directories for supported files and lists them, opens a file directly when given a path, and imports a directory recursively, grouped by format.
- **Reader** — single or split view, adjustable line spacing, selectable themes, optional page numbers, and a table-of-contents overlay.
- **Bookmarks and annotations** — quick bookmarking, in-book annotation notes, an annotations overlay with editing, and mouse selection for highlighting.
- **In-book tools** — full-text search, dictionary lookup, and a translator. The dictionary needs the optional `sqlite3` gem and an installed dictionary. The translator runs **fully offline on your device** using the same neural translation models Firefox ships (downloadable in Settings → Translator, 105 language pairs); a LibreTranslate server is supported as an alternative backend.
- **Inline images** — rendered through the Kitty graphics protocol when the terminal supports it.
- **Downloads** — search and download books through Gutendex or Libgen.
- **RSS reader** — subscribe to feeds and read articles from the menu.
- **Settings** — view mode, line spacing, theme, page numbering, download source, and cache/data management.

## Requirements

- Ruby `>= 3.4.9`. The reader has no third-party gem dependencies, so `bundle install` is not required to run it — only the development and test suites need it.
- Optional: install the `sqlite3` gem (`gem install sqlite3`) to enable dictionary lookup. It is loaded only when the dictionary is used, and is found even when running outside Bundler.
- Optional: build the offline translation engine with `make -C ext/shoko_translate` (needs only a C compiler and `make`; the engine itself has no dependencies beyond libc). Without it the translator falls back to needing a LibreTranslate server.

### Offline translator

The in-app translator runs Mozilla's Firefox translation models (Bergamot
"student" transformers) locally through `ext/shoko_translate`, a small
dependency-free C program that Shoko manages as a child process. Language
packs (~18–35 MB per direction) are downloaded inside the app: **Settings →
Translator** lists every pair Mozilla publishes, downloads with progress and
sha256 verification, and removes packs. Pairs without a direct model are
translated through English automatically, exactly like Firefox does. The
backend row in the same screen switches between the on-device engine
(default) and a LibreTranslate server.

## Usage

```bash
bin/shoko                          # open the library menu
bin/shoko /path/to/book.epub       # open a file directly
bin/shoko /path/to/books-directory # import a directory of supported files
```

Directory import scans recursively, skips hidden files and directories, shows counts by format group (`EPUB`, `PDF`, `FB2`, `Kindle`, `RTF`), and lets you import all files, import one format group, or exit.

### Format support limits

- **Kindle** (`.mobi`, `.azw`, `.azw3`): PalmDOC-compressed, HUFF/CDIC-compressed, and uncompressed books, with embedded images rendered where the terminal supports them. DRM-protected files are rejected with a clear error.
- **PDF**: text extraction supports FlateDecode streams and standard/WinAnsi encodings (plus embedded ToUnicode maps). Encrypted PDFs and exotic stream filters (LZW, ASCII85, JBIG2, …) are not supported; image-only/scanned PDFs yield no text.
- **EPUB/FB2/RTF**: parsed with built-in readers; malformed files are rejected rather than partially rendered.

### CLI options

- `-d`, `--debug` — enable debug logging
- `--log PATH` — write JSON logs to `PATH`
- `--log-level LEVEL` — set the log level (`debug`, `info`, `warn`, `error`, `fatal`)
- `--profile PATH` — write a performance profile to `PATH`
- `--prepaginate-batch SIZE` — pre-paginate every cached library book for `SIZE` (e.g. `220x56`) and exit, printing JSON-line progress; the menu's "Pre-paginate Library" warmup spawns this as a low-priority child process so the menu never competes with it for the CPU
- `-h`, `--help` — print help
- `--version` — print the version

## Controls

### Menus

- `j`/`k` or arrow keys move the selection; `Enter` activates; `Esc` or `q` goes back.
- Library: `Space` toggles the details panel.
- Browse: `/` enters or exits text search.
- Download: `/` query input; `Tab`, `s`, or `S` opens the source selector; `n`/`N` and `p`/`P` page through results; `r` refreshes; `Esc` cancels an active download.

### Reader

- `h`/`l` or `←`/`→` — previous/next page; `Space` — next page
- `j`/`k` or `↑`/`↓` — scroll
- `n`/`N` — next chapter; `p` — previous chapter
- `g`/`G` — start/end of chapter
- `v` — single/split view; `P` — page-numbering mode; `+`/`-` — line spacing
- `t` — table of contents; `/` — in-book search; `d` — dictionary; `T` — translator
- `b` — add bookmark
- `Ctrl+A` — annotations overlay
- `?` — help; `q` — back to menu; `Q` — quit

## Configuration

### Data locations

- Config/data root: `${XDG_CONFIG_HOME:-~/.config}/shoko/`
  - `config.json`, `annotations.json`, `bookmarks.json`, `progress.json`, `recent.json`, `rss_reader.json`
  - `epub_cache.json` — library scan cache (file name retained for compatibility)
  - `downloads/` — downloaded books
  - `translator/models/` — downloaded translation language packs
- Cache root: `${XDG_CACHE_HOME:-~/.cache}/shoko/` — cached book payloads, pagination/layout data, resource blobs, and manifest files

### Environment variables

Logging and profiling mirror the CLI flags:

- `DEBUG=1` — enable debug logging
- `SHOKO_LOG_PATH=PATH` — write JSON logs to a file
- `SHOKO_LOG_LEVEL=LEVEL` — set the log level
- `SHOKO_PROFILE_PATH=PATH` — write a performance profile

Other runtime settings:

- `SHOKO_BOOK_SCAN_DIRS=dir1:dir2` — `PATH`-style list of directories to scan for the library
- `SHOKO_LIBGEN_URL=https://...` — override the Libgen base URL
- `SHOKO_TRANSLATE_URL=http://host:5000` — override the LibreTranslate base URL for the LibreTranslate backend (default `http://127.0.0.1:5000`)
- `SHOKO_TRANSLATE_ENGINE=/path/to/shoko-translate` — override the offline translation engine binary (default: the copy built in `ext/shoko_translate`, then `PATH`)
- `SHOKO_COLOR_MODE=light|dark` — force the color mode instead of detecting it
- `SHOKO_ASCII_ICONS=1` — use ASCII icons instead of glyphs

## Development

Install the development and test gems:

```bash
bundle install
```

Test lanes:

```bash
bundle exec rake test:guardrails   # architecture and wiring guardrails
bundle exec rake test:required     # non-fixture specs across fixed seeds
bundle exec rspec                  # full suite
```

Real-book fixtures (opt-in):

```bash
SHOKO_BOOK_FIXTURES=1 SHOKO_FIXTURES_DIR=/path/to/fixtures bundle exec rake test:fixtures
```

Benchmark scripts live in `script/bench/` (startup first paint, snappiness, and state-store hot path):

```bash
bundle exec ruby script/bench/startup_menu_benchmark.rb
```

End-to-end snappiness benchmarks drive the real `bin/shoko` on a PTY against a
sandboxed library (built once from `testbooks/`, never touching your config or
cache) and measure what a user feels: keypress→paint latency, paint gaps while
background pre-pagination runs, warmup wall time, and reader open/page-turn
latency:

```bash
ruby script/bench/menu_responsiveness_benchmark.rb --sandbox /tmp/shoko-bench --keep --out report.json
ruby script/bench/reader_open_benchmark.rb --sandbox /tmp/shoko-bench --out reader.json
```

### Architecture

Hexagonal layering, enforced by guardrail specs:

- `core` — domain models, services, and reading state
- `application` — use cases, workflows, services, and the `Ports::{Inbound,Outbound}` boundary
- `adapters` — input, UI, output, runtime, storage, monitoring, and the book-source/translation backends
- `composition` — the composition root (`Shoko::Composition::ContainerFactory`); the only layer that resolves the container

```text
lib/shoko/
  core/{models,services,events,reading}
  application/{ports/{inbound,outbound},use_cases,services,workflows,state}
  adapters/{input,ui,output,runtime,storage,monitoring,book_sources,rss,translation}
  composition/
  shared/
```

The driving boundary is `Application::Ports::Inbound::{ReaderIntentHandler,MenuIntentHandler}`, implemented by the matching `Application::UseCases` handlers; `Application::Ports::Outbound::*` is the driven surface implemented by adapters. Further notes are in [docs/architecture/constitution.md](docs/architecture/constitution.md).

## License

MIT. See [LICENSE](LICENSE).
