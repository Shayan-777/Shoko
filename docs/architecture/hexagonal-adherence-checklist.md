# Hexagonal Architecture Adherence Checklist (Zero-Fallback Cutover)

Date: 2026-03-03  
Scope: `lib/shoko/**` runtime + architecture guardrails/spec gates

## Completed

- [x] Removed optional DI resolution usage:
  - zero `resolve_optional(` occurrences in `lib/shoko`.
  - `DependencyContainer` exposes mandatory `resolve` only.
- [x] Removed two-phase reader runtime wiring from public API:
  - no `defer_runtime_setup`.
  - no `attach_runtime_components!`.
  - reader runtime graph is single-phase via constructor-time runtime factory.
- [x] Completed inbound boundary ownership migration:
  - adapters no longer include inbound intent handler ports.
  - adapter loopback intent handlers removed.
  - application intent handlers added under `application/use_cases/intents`.
- [x] Removed reflection-style probing/dispatch globally in runtime code:
  - zero `respond_to?(` occurrences.
  - zero `public_send` occurrences.
  - zero dynamic `send(` occurrences.
- [x] Removed collaborator-probing rescues:
  - zero `rescue NoMethodError` collaborator probing occurrences.
- [x] Removed broad `rescue StandardError` usage in runtime code:
  - zero `rescue StandardError` occurrences in `lib/shoko`.
- [x] Removed known swallow/fallback runtime behaviors in strict paths:
  - annotation refresh now fails fast.
  - reader quit/save progress now fails fast.
  - event bus subscriber failures are logged then re-raised.
  - render state writer failures are logged then re-raised.
  - document path resolver no longer masks resolver failures.
  - kitty image line renderer no longer suppresses renderer exceptions.
- [x] Boundary translation hardened:
  - document load failures are translated to `Shoko::BookParseError`.
  - dictionary catalog boundary uses typed `CatalogError < Shoko::Error`.
  - cache import boundary uses typed `ImportError < Shoko::Error`.

## Open Items

- [ ] Persist benchmark baselines and enforce CI threshold checks.
- [ ] Fixture lane is blocked locally by missing required books (see verification snapshot).

## Verification Checklist

- [x] `bundle exec rspec spec/core/architecture spec/bootstrap/dependencies`
- [x] `bundle exec rake test:guardrails`
- [x] `bundle exec rake test:required`
- [x] `bundle exec rspec`
- [ ] `bundle exec rake test:fixtures` (blocked locally)

## Verification Snapshot

- `bundle exec rspec spec/core/architecture spec/bootstrap/dependencies`:
  - 81 examples, 0 failures.
- `bundle exec rake test:guardrails`:
  - pass.
- `bundle exec rake test:required`:
  - pass for seeds `10101`, `20202`, `30303`.
- `bundle exec rspec`:
  - 935 examples, 0 failures.
- `bundle exec rake test:fixtures`:
  - blocked by missing files:
    - `Persuasion (Jane Austen).mobi`
    - `Pride Prejudice (Jane Austen).azw`
    - `Emma (Jane Austen).azw3`
    - `Pride And Prejudice (Austen Jane).rtf`
- Artifact sweeps (`lib/shoko`):
  - `resolve_optional(`: `0`
  - `rescue StandardError`: `0`
  - `rescue NoMethodError` probing: `0`
  - `respond_to?` / `public_send` / dynamic `send(`: `0`
