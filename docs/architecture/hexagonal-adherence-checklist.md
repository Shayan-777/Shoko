# Hexagonal Architecture Adherence Checklist (Strict)

Date: 2026-03-03  
Scope: strict migration boundary (`lib/shoko/core`, `lib/shoko/application`, `lib/shoko/adapters/runtime`, `lib/shoko/bootstrap`) plus high-risk book-loading path

## Completed

- [x] Inbound command boundary is intent-based (`ReaderIntentHandler` / `MenuIntentHandler`) with one dispatch entrypoint per adapter context.
- [x] Command bus registry routes symbols to explicit intent commands (`ReaderIntentCommand`, `MenuIntentCommand`, `SharedIntentCommand`).
- [x] Removed legacy gateway-style inbound contracts and command classes.
- [x] Pagination preload/orchestration uses split outbound ports (`PaginationStateWriter`, `ReaderStateWriter`, `UiLoadingWriter`, `SidebarStateReader`).
- [x] `BookmarkService` and `UnifiedApplication` sidebar visibility reads use `SidebarStateReader`.
- [x] `PageInfoCalculator` terminal-change logic uses `UiStateReader#terminal_size_changed?` with no fallback branch.
- [x] Runtime launch workflow removed non-contract debug state reads.
- [x] Reader runtime composition is bootstrap-only and assembled in `bootstrap/container_factory/controller_composition/reader_builder.rb`.
- [x] Late setter wiring for reader graph composition was removed; collaborators are injected at build time.
- [x] Bootstrap menu composition no longer uses private helper dispatch (`menu.send(...)`).
- [x] Semantic reader commands use typed inbound contracts (`ReaderNavigationCommandContext`, `ReaderBookmarkCommandContext`).
- [x] Reader-launch orchestration uses typed collaborator contracts (`ReaderLaunch::Contracts::*`) and strict dependency validation.
- [x] CLI folder import workflow collaborators are typed (`FolderScanner` / `FolderImporter`) and workflow-level reflection probing was removed.
- [x] Dictionary failure semantics are typed and adapter-normalized (`Core::Errors::DictionaryFailure`, typed repository errors).
- [x] Added strict reader contracts for core/application services:
  - `Core::Ports::Outbound::ReaderDocument`
  - `Core::Ports::Outbound::ReaderChapter`
- [x] Removed reflection probing in strict migration scope:
  - no `respond_to?`, `public_send`, or dynamic `send` usage in `core`, `application`, `adapters/runtime`, `bootstrap`.
- [x] Removed synthetic error-document fallback path from book loading:
  - deleted `ErrorDocument`/`ErrorChapter` usage in document service/cache import flow.
  - failures now propagate via explicit parse/import errors.
- [x] Navigation state updates no longer leak `%i[reader ...]` paths in application navigation orchestration.
- [x] Metadata extractors (`RTF`, `Kindle`) now enforce `PathOps` contracts without masking contract violations.
- [x] Guardrails expanded and passing:
  - strict-scope reflection/dispatch guardrail.
  - synthetic error-document fallback tombstones.
  - existing architecture guardrails (`spec/core/architecture`) remain green.
- [x] Removed reflective command dispatch/probing from targeted input/menu adapters:
  - `adapters/input/command_factory.rb`
  - `adapters/input/controllers/menu/controller.rb`
  - `adapters/input/controllers/menu/actions/dictionary_actions.rb`
  - `adapters/input/controllers/reader_controller.rb` intent dispatch helper removal
- [x] Removed capability probing in targeted UI session adapters:
  - `adapters/ui/sessions/dictionary_ui_session_adapter.rb`
  - `adapters/ui/sessions/in_book_search_ui_session_adapter.rb`
  - `adapters/ui/sessions/annotation_overlay_ui_session_adapter.rb`
- [x] Removed reflective checks in targeted sidebar/reader interaction paths:
  - `adapters/input/controllers/sidebar_controller.rb`
  - `adapters/input/controllers/sidebar/toc_facade.rb`
  - `adapters/input/controllers/sidebar_mouse_handler.rb`
  - `adapters/input/controllers/mouseable_reader.rb`
  - `adapters/input/controllers/reader/input_router.rb`
  - `adapters/input/controllers/in_book_search_controller.rb`
- [x] CLI strict break applied:
  - removed compatibility alias `Shoko::CLI`
  - removed shape-probing (`read_object_field`, `respond_to?`/`public_send` checks)
  - folder import flow now uses typed context/report/document/failure contracts.
- [x] Book loading cross-adapter runtime construction removed from `BookDocument`:
  - `BookDocument` now requires injected `book_cache` pipeline collaborator.
  - pipeline composition moved into bootstrap document-service builder.

## Remaining Work

- [ ] Persist benchmark baselines and enforce CI regression thresholds for startup/render performance.
- [ ] Reduce composition/dependency fan-in in `bootstrap/container_factory/controller_composition/reader_builder.rb` (still a large orchestration hotspot).
- [ ] Complete global reflection elimination in all `lib/shoko` (current snapshot still has 88 matches of `respond_to?`/`public_send`/dynamic `send`).
- [ ] Eliminate broad rescue usage in all `lib/shoko` (current snapshot still has 491 `rescue StandardError` occurrences).
- [ ] Remove runtime optional DI resolution (`resolve_optional`) from runtime/bootstrap composition paths (current snapshot still has 129 occurrences).
- [ ] Continue strict contract migration in remaining adapter rendering/storage/helpers (outside strict boundary), especially:
  - `adapters/ui/rendering/*`
  - `adapters/output/*`
  - `adapters/storage/*`
- [ ] Split `reader_builder` composition fan-in and remove optional runtime fallback behavior fully.

## Verification Checklist

- [x] `bundle exec rspec spec/core/architecture spec/bootstrap/dependencies`
- [x] `bundle exec rake test:guardrails`
- [x] `bundle exec rake test:required`
- [x] `bundle exec rspec`
- [x] Artifact sweeps:
  - zero `respond_to?` / `public_send` / dynamic `send` in strict migration boundary.
  - zero `ErrorDocument` / `ErrorChapter` artifacts in active book-loading pipeline.
- [ ] Fixture lane (`bundle exec rake test:fixtures`) - blocked locally by missing required fixture books.

## Verification Snapshot

- `bundle exec rspec spec/core/architecture spec/bootstrap/dependencies`:
  - 81 examples, 0 failures.
- `bundle exec rake test:guardrails`:
  - 85 examples, 0 failures.
- `bundle exec rake test:required`:
  - pass for seeds `10101`, `20202`, `30303` (935 examples each, 0 failures).
- `bundle exec rspec`:
  - 935 examples, 0 failures (`--tag ~requires_book_fixtures` default exclusion).
- `bundle exec rake test:fixtures`:
  - failed due missing local fixture files (`Persuasion.mobi`, `Pride Prejudice.azw`, `Emma.azw3`, `Pride And Prejudice.rtf`).
- Artifact sweep:
  - zero reflection probing (`respond_to?`/`public_send`/dynamic `send`) in strict migration boundary.
  - zero synthetic error-document fallback artifacts in the active book-loading path.
  - global `lib/shoko` debt snapshot:
    - reflection probes: `88`
    - broad rescue (`rescue StandardError`): `491`
    - optional DI (`resolve_optional`): `129`
