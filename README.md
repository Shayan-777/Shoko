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
- `core` contains domain models/services and the single ports root.
- Ports are split by direction only:
- `Core::Ports::Inbound::*` (driving boundary into application use cases).
- `Core::Ports::Outbound::*` (driven dependencies implemented by adapters).
- `application` contains use-case/workflow/service orchestration only.
- `adapters` contains all input, UI, output, runtime, monitoring, and storage implementations.
- `bootstrap` is the only composition root and the only layer that mutates/resolves the container.
- Reader runtime controller graph composition is bootstrap-only (`ContainerFactory::ControllerComposition::ReaderBuilder`).

Canonical runtime layout:

```text
lib/shoko/
  core/ports/{inbound,outbound}
  application/{use_cases,services,workflows}
  adapters/{input,ui,output,runtime,storage,monitoring}
  bootstrap/{container_factory,dependencies}
  shared/
```

Inbound command boundary:

- `Core::Ports::Inbound::CommandBus`
- `Core::Ports::Inbound::ReaderIntentHandler`
- `Core::Ports::Inbound::MenuIntentHandler`
- Implemented by `Application::UseCases::CommandBus`
- Input symbols are dispatched through `ReaderIntentCommand`, `MenuIntentCommand`, and `SharedIntentCommand`

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

Import a folder of ebooks from CLI:

```bash
bin/start /path/to/books-directory
```

This scans the directory recursively (skipping hidden files/folders), shows counts by format, and lets you:

- import all discovered files
- import only one file type
- exit without importing

After import, Shoko opens menu mode by default.

Options:

- `-d`, `--debug` Enable debug logging.
- `--log PATH` Write JSON logs to PATH.
- `--log-level LEVEL` Set log level (`debug`, `info`, `warn`, `error`, `fatal`).
- `--profile PATH` Write a concise performance profile to PATH.
- `-v`, `--version` Show version.
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

## Logging and profiling

You can also configure logging with environment variables:

- `DEBUG=1` Enable debug logging.
- `SHOKO_LOG_PATH=/path/to/log` Write JSON logs to a file.
- `SHOKO_LOG_LEVEL=info` Set log level.
- `SHOKO_PROFILE_PATH=/path/to/profile` Write a performance profile.

## Testing

Required guardrails lane:

```bash
bundle exec rake test:guardrails
```

Required non-fixture lane (runs 3 fixed seeds):

```bash
bundle exec rake test:required
```

Real-book fixture lane:

```bash
SHOKO_BOOK_FIXTURES=1 SHOKO_FIXTURES_DIR=/path/to/book-fixtures bundle exec rake test:fixtures
```

Full suite sanity:

```bash
bundle exec rspec
```

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
