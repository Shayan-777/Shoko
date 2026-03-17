# Shoko Cleanup Plan

## Done Means
- `bundle exec rake test:guardrails` passes.
- `bundle exec rake test:required` passes on seeds `10101`, `20202`, and `30303`.
- No references remain to removed session wrappers: `config_view`, `reader_session_view`, `menu_session_view`, `reader_ui_state_view`.
- [README.md](/home/shayan/Shoko/README.md) links to a real runtime handoff document.

## Milestones
1. Guardrail Gate
2. Session Schema
3. State API
4. Reader Composition
5. Menu Composition
6. Docs And Polish
7. Deferred Debt

## Baseline
- `bundle exec rake test:guardrails`: red
- `bundle exec rake test:required`: red on seeds `10101`, `20202`, `30303`
- `docs/architecture/runtime_handoff.md`: missing
- `bundle exec ruby script/bench/startup_menu_benchmark.rb -n 3 -w 1`: about `387 ms` total first paint

## Done
- `bundle exec rake test:guardrails` passes.
- `bundle exec rake test:required` passes on seeds `10101`, `20202`, and `30303`.
- Guardrail blockers removed:
  - no rescue-literal config fallback in reader startup
  - no rescue-literal source fallback in kitty rendering
  - chapter metadata normalized once in image cache warmup
  - reader warmup services grouped into `ReaderWarmupServices`
- Canonical session schema added in `Session::Schema`.
- `app_config_store`, `reader_session_store`, and `menu_session_store` now expose `update`.
- Removed session wrapper registrations and deleted wrapper files:
  - `config_view`
  - `reader_session_view`
  - `menu_session_view`
  - `reader_ui_state_view`
- Direct store/runtime-context wiring now drives menu and reader composition.
- Reader composition collapsed into `reader_builder/assembly.rb` with grouped runtime contexts:
  - `ReaderPlatformContext`
  - `ReaderStateContext`
  - `ReaderUiContext`
  - `ReaderServiceContext`
- Added focused specs for session schema, store update behavior, and wrapper removal guardrails.
- Added `docs/architecture/runtime_handoff.md`.
- Split `settings_screen_component.rb` into smaller selection/value/detail helpers.
- Replaced unconditional eager top-level boot in `lib/shoko.rb` with a minimal runtime loader.
- Kept eager runtime boot available for tests and explicit diagnostics via `SHOKO_TEST_MODE=1` or `SHOKO_EAGER_BOOT=1`.
- Made `ContainerFactory` runtime dependencies explicit enough to boot menu mode without `RuntimeComposition.boot!`.
- Fixed a hidden UI require bug by adding `annotation_detail_screen_component` to `main_menu_component.rb`.
- Updated the startup benchmark harness to load the real menu controller before patching `main_loop`.
- Startup benchmark regression resolved:
  - `bundle exec ruby script/bench/startup_menu_benchmark.rb -n 3 -w 1`
  - `require_ms mean=319.13`
  - `run_ms mean=68.40`
  - `total_ms mean=387.54`
- Menu boot now defers inactive workflows and reader-launch services behind lazy proxies instead of resolving them during controller construction.
- `MainMenuComponent` now instantiates non-active screens on demand instead of building every menu screen up front.
- `ContainerFactory` no longer top-loads several reader-only and mode-specific classes that are now required at the point of first resolution.
- Added a focused menu controller spec to guard against eager resolution of inactive workflows and reader-launch services.
- Current short startup benchmark after the extra trim:
  - `bundle exec ruby script/bench/startup_menu_benchmark.rb -n 3 -w 1`
  - `require_ms mean=307.79`
  - `run_ms mean=74.37`
  - `total_ms mean=382.18`
- Plain `require 'shoko'` no longer loads the deferred reader-only composition, reader UI components, or reader/CLI runtime adapters guarded by `plain_require_boot_surface_guardrails_spec`.
- Startup benchmark after removing the remaining plain-require reader-only load:
  - `bundle exec ruby script/bench/startup_menu_benchmark.rb -n 5 -w 1`
  - `require_ms mean=177.31`
  - `run_ms mean=60.28`
  - `total_ms mean=237.60`
- Deferred reader-launch services that reference `Core::Models::ReaderSettings` now load that model explicitly instead of relying on eager boot side effects.
- Added a subprocess regression guard to ensure deferred reader services can load `ReaderSettings` without `SHOKO_TEST_MODE=1`.
- The lazy reader-builder path now explicitly loads `mouseable_reader.rb` before `reader_builder/assembly.rb` instantiates `MouseableReader`.
- Added a subprocess regression guard to ensure `require 'shoko'` plus `require '.../reader_builder'` loads the concrete reader controller classes needed by deferred reader launch.
- The deferred `xhtml_parser_factory` now explicitly loads `epub/parser/xhtml_content_parser.rb` before constructing `XHTMLContentParser`.
- Added a subprocess regression guard to ensure the container can resolve and execute `:xhtml_parser_factory` without `SHOKO_TEST_MODE=1`.
- The reader content first-paint path now explicitly loads `single_view_renderer.rb` and `split_view_renderer.rb` before `ViewRendererFactory` instantiates them.
- Added a subprocess regression guard to ensure `ViewRendererFactory` can build both single and split renderers under plain boot.
- The quoted-line render path now explicitly loads `constants/highlighting.rb` before `InlineSegmentHighlighter` and `LineContentComposer` use `Constants::Highlighting`.
- Added a plain-boot reader render smoke guard that builds both renderers and draws a highlighted display line through `LineDrawer` without eager boot.

## In Progress
- Deferred Debt

## Next
- Decide whether `reader_builder/assembly.rb` should stay monolithic or be further compressed without reintroducing the old indirection.
- Audit the next deferred reader-launch/runtime path for implicit constant loading beyond `ReaderSettings`, especially reader UI sessions and runtime context helpers.
- Audit the rest of the deferred reader-launch/runtime path for any remaining implicit constant loading beyond the controller classes now covered by the lazy reader-builder guard.
- Audit the remaining deferred book-format/render pipeline for any implicit constant loading beyond the XHTML parser path now covered by the lazy factory guard.
- Audit the remaining deferred reader render subtree for any implicit constant loading beyond the view-renderer factory path now covered by the plain-boot renderer guard.
- Audit the remaining deferred reader render subtree for any implicit constant loading beyond the highlighted line-composition path now covered by the plain-boot render smoke guard.
- Check whether menu `run_ms` can come down further now that `require_ms` is lower, without reintroducing eager service graphs.
- Triage remaining non-guardrail style debt separately from this structural cleanup lane.

## Blocked
- None currently.

## Health Checks
- Re-run `bundle exec rake test:guardrails` after each structural phase.
- Re-run `bundle exec rake test:required` before closing the refactor lane.
- Re-run `bundle exec ruby script/bench/startup_menu_benchmark.rb -n 3 -w 1` after composition cleanup.
