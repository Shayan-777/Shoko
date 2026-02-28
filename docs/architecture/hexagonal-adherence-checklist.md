# Hexagonal Architecture Adherence Checklist (Strict)

Date: 2026-02-28  
Scope: full repository scan (`lib/`, `spec/`, bootstrap wiring, architecture guardrails)

## Completed

- [x] Inbound command boundary is intent-based (`ReaderIntentHandler` / `MenuIntentHandler`) with one dispatch entrypoint per adapter context.
- [x] Command bus registry routes symbols to explicit intent commands (`ReaderIntentCommand`, `MenuIntentCommand`, `SharedIntentCommand`).
- [x] Removed legacy gateway-style inbound contracts and command classes.
- [x] Pagination preload/orchestration now uses split outbound ports:
  - `PaginationStateWriter` for pagination mutations only.
  - `ReaderStateWriter` for terminal/config/reader state updates.
  - `UiLoadingWriter` for loading overlays.
  - `SidebarStateReader` for sidebar visibility/layout decisions.
- [x] `BookmarkService` and `UnifiedApplication` sidebar visibility reads now use `SidebarStateReader`.
- [x] `PageInfoCalculator` terminal-change logic now uses `UiStateReader#terminal_size_changed?` with no fallback branch.
- [x] Runtime launch workflow removed non-contract debug state reads.
- [x] Reader runtime composition is bootstrap-only:
  - Adapter-side reader runtime bootstrap helper classes were deleted.
  - `UIController` no longer composes sibling controllers internally.
  - Reader controller graph is assembled in `bootstrap/container_factory/controller_composition/reader_builder.rb`.
- [x] Late setter wiring for reader graph composition was removed; collaborators are injected at build time.
- [x] Guardrails expanded:
  - Port-method contract usage checks in application layer.
  - Controller composition locality checks (bootstrap-only for reader graph).
  - Constructor budget parser migrated to AST-based parsing.
  - No-legacy tombstones for removed inbound/runtime artifacts.
- [x] Bootstrap menu composition no longer uses private helper dispatch (`menu.send(...)`):
  - `menu_builder.rb` now calls explicit public workflow methods on menu controller.
  - Menu bridge adapters bind directly to those public methods.
- [x] Semantic reader commands now use typed inbound contracts:
  - `ReaderNavigationCommandContext` and `ReaderBookmarkCommandContext` enforce command context shape.
  - `NavigationCommand` / `BookmarkCommand` validate via `is_a?` contract checks.
  - Application command base no longer uses UI fallback (`show_error_message`) hooks.
- [x] Reader-launch orchestration now uses typed collaborator contracts:
  - `ReaderLaunch::Contracts::{PathResolution,DocumentPreparation,RuntimeExecution,ProgressOrchestration}`.
  - `ReaderLaunchService::Dependencies` validates collaborators via strict `is_a?` checks.
- [x] Guardrails hardened for the new migration constraints:
  - Forbid `menu.send(` in bootstrap menu composition.
  - Forbid `context.respond_to?` capability checks in application command use-cases.
  - Forbid `respond_to?`-based collaborator validation in `ReaderLaunchService`.
  - Layer dependency scan now includes both `require_relative` and `require 'shoko/...'` imports.

## Remaining Work

- [ ] Persist benchmark baselines and enforce CI regression thresholds for startup/render performance.

## Verification Checklist

- [x] `bundle exec rspec spec/core/architecture spec/bootstrap/dependencies`
- [x] `bundle exec rake test:guardrails`
- [x] `bundle exec rake test:required`
- [x] `bundle exec rspec`
- [x] Artifact sweeps:
  - zero matches for removed gateway/runtime artifact identifiers in `lib/`, `spec/`, `docs/`, and `README.md` (excluding architecture tombstone guardrail specs)

## Verification Snapshot

- `bundle exec rspec spec/core/architecture spec/bootstrap/dependencies`:
  - 73 examples, 0 failures.
- `bundle exec rake test:guardrails`:
  - 77 examples, 0 failures.
- `bundle exec rake test:required`:
  - pass for seeds `10101`, `20202`, `30303` (916 examples each, 0 failures).
- `bundle exec rspec`:
  - 916 examples, 0 failures (`--tag ~requires_book_fixtures` default exclusion).
- Artifact sweep:
  - zero matches for `menu.send(` in runtime source.
  - zero `respond_to?` capability checks in `application/use_cases/commands/*.rb`.
  - zero `respond_to?` collaborator validation checks in `application/workflows/menu/reader_launch_service.rb`.
