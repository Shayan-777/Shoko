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
- [x] CLI folder import workflow collaborators are typed (`FolderScanner` / `FolderImporter`) and reflection probing was removed.
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

## Remaining Work

- [ ] Persist benchmark baselines and enforce CI regression thresholds for startup/render performance.
- [ ] Reduce composition/dependency fan-in in `bootstrap/container_factory/controller_composition/reader_builder.rb` (still a large orchestration hotspot).
- [ ] Continue strict contract migration in adapter-heavy UI/controller layers still using capability probing:
  - `adapters/ui/sessions/*`
  - `adapters/input/controllers/sidebar/*`
  - `adapters/input/command_factory.rb`
  - `adapters/ui/rendering/*`
- [ ] Remove remaining legacy fallback/shape-probing in adapter infra (outside strict migration boundary), especially in metadata/render/storage adapter helpers.

## Verification Checklist

- [x] `bundle exec rspec spec/core/architecture spec/bootstrap/dependencies`
- [x] `bundle exec rake test:guardrails`
- [x] `bundle exec rake test:required`
- [x] `bundle exec rspec`
- [x] Artifact sweeps:
  - zero `respond_to?` / `public_send` / dynamic `send` in strict migration boundary.
  - zero `ErrorDocument` / `ErrorChapter` artifacts in active book-loading pipeline.

## Verification Snapshot

- `bundle exec rspec spec/core/architecture spec/bootstrap/dependencies`:
  - 81 examples, 0 failures.
- `bundle exec rake test:guardrails`:
  - 85 examples, 0 failures.
- `bundle exec rake test:required`:
  - pass for seeds `10101`, `20202`, `30303` (934 examples each, 0 failures).
- `bundle exec rspec`:
  - 934 examples, 0 failures (`--tag ~requires_book_fixtures` default exclusion).
- Artifact sweep:
  - zero reflection probing (`respond_to?`/`public_send`/dynamic `send`) in strict migration boundary.
  - zero synthetic error-document fallback artifacts in the active book-loading path.
