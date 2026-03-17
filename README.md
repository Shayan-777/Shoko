# Shoko

Terminal ebook reader for supported ebook documents:
`.epub`, `.fb2`, `.pdf`, `.mobi`, `.azw`, `.azw3`, and `.rtf`.

## What It Does

- Scans common user directories for supported ebook files and shows them in a menu.
- Opens a supported file directly when a path is provided.
- When given a directory path, recursively discovers supported files, groups them by format, and lets you import all files, import one format group, or exit.
- Reads in single or split view with adjustable line spacing, themes, optional page numbers, an in-book search flow, TOC/bookmark/annotation sidebars, and annotation editing.
- Supports mouse selection for highlighting and annotation workflows.
- Downloads books through Gutendex or Libgen.
- Supports optional dictionary lookup when a dictionary backend is configured.
- Supports terminal inline image rendering via the Kitty graphics protocol when enabled and supported by the terminal.

## How It Works

- `bin/shoko` is the CLI entrypoint.
- `composition` is the runtime wiring boundary (`Shoko::Composition::ContainerFactory`).
- State lives behind direct session/config stores, with `reader_runtime_context` covering terminal and live runtime reads.
- Rendering is component-based and drawn through a terminal buffer with diff updates.
- Selection and highlighting use line geometry recorded during render.

## Architecture Boundaries

- Hexagonal layering is enforced.
- `core` contains domain models/services and the ports root.
- `Core::Ports::Inbound::*` is the driving boundary into application use cases.
- `Core::Ports::Outbound::*` is the driven dependency surface implemented by adapters.
- `application` contains use cases, workflows, and orchestration services.
- `adapters` contains input, UI, output, runtime, monitoring, and storage implementations.
- `composition` is the composition root and the only layer that mutates/resolves the container.
- Reader composition groups runtime wiring into platform/state/UI/service contexts instead of one giant record.

Canonical runtime layout:

```text
lib/shoko/
  core/ports/{inbound,outbound}
  application/{use_cases,services,workflows}
  adapters/{input,ui,output,runtime,storage,monitoring}
  composition/{container_factory,dependencies}
  shared/
```

Inbound intent boundary:

- `Core::Ports::Inbound::ReaderIntentHandler`
- `Core::Ports::Inbound::MenuIntentHandler`
- Implemented by `Application::UseCases::ReaderIntentHandler`
- Implemented by `Application::UseCases::MenuIntentHandler`

Runtime startup and the menu/reader handoff are documented in [docs/architecture/runtime_handoff.md](/home/shayan/Shoko/docs/architecture/runtime_handoff.md).

## Usage

From source:

```bash
bundle install
bin/shoko
```

Open a supported file directly:

```bash
bin/shoko /path/to/book.pdf
```

Import a folder of supported ebooks from the CLI:

```bash
bin/shoko /path/to/books-directory
```

Supported extensions:

- `.epub`
- `.fb2`
- `.pdf`
- `.mobi`
- `.azw`
- `.azw3`
- `.rtf`

Directory import behavior:

- scans recursively
- skips hidden files and directories
- shows counts by format group (`EPUB`, `PDF`, `FB2`, `Kindle`, `RTF`)
- lets you import all files, import one format group, or exit

CLI options:

- `-d`, `--debug` enable debug logging
- `--log PATH` write JSON logs to `PATH`
- `--log-level LEVEL` set log level (`debug`, `info`, `warn`, `error`, `fatal`)
- `--profile PATH` write a concise performance profile to `PATH`
- `-h`, `--help` print help

## Common Controls

Menu lists:

- `j`/`k` or arrow keys move selection
- `Enter` activates the selected item
- `Esc` or `q` goes back

Browse mode:

- `/` enters or exits text search

Library mode:

- `Space` toggles the details drawer

Download mode:

- `/` enters or exits query input
- `Tab`, `s`, or `S` opens the download-source selector
- `n`/`N` moves to the next results page
- `p`/`P` moves to the previous results page
- `r` refreshes results

Reader:

- `h`/`l` or left/right arrows move page
- `Space` moves to the next page
- `j`/`k` or up/down arrows scroll
- `n`/`N` goes to the next chapter
- `p` goes to the previous chapter
- `g` jumps to the start, `G` jumps to the end
- `v`/`V` toggles single/split view
- `P` toggles page numbering mode
- `+`/`-` adjusts line spacing
- `t`/`T` opens the TOC sidebar
- `b` adds a bookmark, `B` opens the bookmarks sidebar
- `A` opens the annotations sidebar
- `s` opens in-book search
- `?` opens help
- `q` returns to menu, `Q` quits the application

## Data Locations

- Config/data root: `${XDG_CONFIG_HOME:-~/.config}/shoko/`
- Stored config/data files:
  - `config.json`
  - `annotations.json`
  - `bookmarks.json`
  - `progress.json`
  - `recent.json`
  - `epub_cache.json` (library scan cache; file name retained for compatibility)
  - `downloads/` (downloaded books from configured sources)
- Cache root: `${XDG_CACHE_HOME:-~/.cache}/shoko/`
- Cache root contents include cached book payloads, pagination/layout data, resource blobs, and manifest files

## Logging And Runtime Configuration

Logging and profiling can also be configured with environment variables:

- `DEBUG=1` enables debug logging
- `SHOKO_LOG_PATH=/path/to/log` writes JSON logs to a file
- `SHOKO_LOG_LEVEL=info` sets the log level
- `SHOKO_PROFILE_PATH=/path/to/profile` writes a performance profile
- `SHOKO_LIBGEN_URL=https://...` overrides the Libgen base URL used by the download source

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

Startup menu first-paint benchmark:

```bash
bundle exec ruby script/bench/startup_menu_benchmark.rb
```

Dynamic pagination sidebar-toggle benchmark:

```bash
bundle exec ruby script/bench/sidebar_toggle_layout_benchmark.rb
```

Snappiness microbenchmark:

```bash
bundle exec ruby script/bench/snappiness_benchmark.rb
```

The snappiness benchmark prints baseline vs optimized timings for:

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
