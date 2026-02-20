# Shoko

Terminal ebook reader for EPUB files.

## What it does

- Scans common folders for EPUB files and shows them in a menu.
- Opens a specific file directly when a path is provided.
- Reads in split or single view with adjustable line spacing and themes.
- Provides a TOC sidebar, bookmarks, and annotations.
- Supports mouse selection for highlighting and annotation editing.
- Can download public-domain EPUBs from Gutendex.
- Optional Kitty inline image rendering (when supported).

## How it works

- `bin/start` runs the CLI and enters menu mode or opens a file directly.
- `bootstrap` is the only runtime wiring boundary (`Bootstrap::ContainerFactory`).
- State lives in a single store; actions update state and selectors read it.
- Rendering is component-based and drawn through a terminal buffer with diff updates.
- Selection/highlighting uses recorded line geometry from the render pass.

## Architecture boundaries

- Hexagonal layering is enforced.
- `core` contains parsing/domain logic and domain/infrastructure-facing ports.
- `application` orchestrates workflows through application-owned contracts.
- `adapters` own IO/runtime/storage/integration implementation details.
- `presentation/ui` is the dedicated UI subsystem (components, sessions, rendering models/pipeline).
- `bootstrap` is the top-level composition root outside application/core/adapters.
- Infrastructure ports for IO/process/time remain core-owned:
- `Core::Ports::FileProbe`
- `Core::Ports::PathOps`
- `Core::Ports::ProcessControl`
- `Core::Ports::Clock`
- `Core::Ports::EventPublisher`
- Application-owned orchestration and UI/input contracts include:
- `Application::Ports::ConfigReader`
- `Application::Ports::ReaderNavigationReader`
- `Application::Ports::KeyClassifier`
- `Application::Ports::NotificationWriter`
- `Application::Ports::UiComponentFactory`
- `Application::Ports::RenderingFactory`
- `Application::Ports::RenderStateWriter`
- `Application::Ports::ReaderOverlayStateReader`
- `Application::Ports::UiStateReader`, `Application::Ports::SidebarStateReader`
- `Application::Ports::PaginationStateWriter`, `Application::Ports::ReaderStateWriter`
- `Application::Ports::InputSystemFactory`
- `Application::Ports::MenuNavigationReader`, `Application::Ports::MenuQueryReader`, `Application::Ports::MenuDataReader`
- `Application::Ports::DictionaryUiSession`
- `Application::Ports::InBookSearchUiSession`
- `Application::Ports::AnnotationOverlayUiSession`
- `Application::Ports::CommandPort`

## Usage

From source:

```bash
bundle install
bin/start
```

Open a file directly:

```bash
bin/start /path/to/book.epub
```

Options:

- `-d`, `--debug` Enable debug logging.
- `--log PATH` Write JSON logs to PATH.
- `--log-level LEVEL` Set log level (`debug`, `info`, `warn`, `error`, `fatal`).
- `--profile PATH` Write a concise performance profile to PATH.
- `-h`, `--help` Show help.

## Controls (basics)

Menu:

- `j`/`k` or arrow keys to move
- `Enter` to select
- `Esc` to go back
- `/` to search in browse mode
- `q` to quit

Reader:

- `h`/`l` or arrow keys to change pages
- `j`/`k` to scroll
- `Space` for next page
- `t` for TOC
- `b` to add bookmark, `B` to open bookmarks
- `A` to open annotations
- `?` for help
- `q` to return to menu, `Q` to quit

## Data locations

- Config and data: `~/.config/shoko/`
  - `config.json`
  - `annotations.json`, `bookmarks.json`, `progress.json`, `recent.json`
  - `downloads/` (Gutendex downloads)
- Cache: `~/.cache/shoko/`

## Migration (v2)

- Startup now blocks when legacy data is detected without a migration marker.
- Run one-time migration:
  - `bin/migrate-v2`
- Roll back to latest backup:
  - `bin/migrate-v2-rollback`
- Backups are written under `~/.config/shoko-backups/`.

## Logging and profiling

You can also configure logging with environment variables:

- `DEBUG=1` Enable debug logging.
- `SHOKO_LOG_PATH=/path/to/log` Write JSON logs to a file.
- `SHOKO_LOG_LEVEL=info` Set log level.
- `SHOKO_PROFILE_PATH=/path/to/profile` Write a performance profile.

## Benchmarking

Run the built-in snappiness benchmark:

```bash
bundle exec ruby script/bench/snappiness_benchmark.rb
```

The benchmark prints baseline vs optimized timings for:

- `TextMetrics.visible_length` cache impact
- `TextMetrics.visible_length` ASCII fast-path impact
- `TextMetrics.truncate_to` ASCII fast-path impact
- `TextMetrics.wrap_plain_text` cache impact
- `TextMetrics.wrap_plain_text` result-cache impact
- `LineAssembler.build` cache impact
- `LineAssembler::Tokenizer.tokenize` cache impact
- `LineAssembler.build` tokenize-cache impact
- `LineAssembler.build` token-width-hints impact
- `LineAssembler.build` token-pipeline combined impact
- `WrappingService.wrap_window` prefetch-range reuse impact
- `LineGeometryBuilder.build` repeated-line cell cache impact
- `TerminalBuffer::Frame.write` ASCII fast-path impact
- `LineContentComposer.compose` repeated-line cache impact
- `ManifestShaFinder.sha` large-manifest lookup impact
- `JsonCacheStore.manifest_rows` repeated-read cache impact
