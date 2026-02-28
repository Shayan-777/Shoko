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
  - 70 examples, 0 failures.
- `bundle exec rake test:guardrails`:
  - pass.
- `bundle exec rake test:required`:
  - pass for seeds `10101`, `20202`, `30303`.
- `bundle exec rspec`:
  - 897 examples, 0 failures (`--tag ~requires_book_fixtures` default exclusion).
- Artifact sweep:
  - no matches for removed gateway/runtime identifiers outside dedicated tombstone guardrail specs.
