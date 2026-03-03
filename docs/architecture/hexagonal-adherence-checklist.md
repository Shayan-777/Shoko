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
  - adapter-owned intent handler classes removed.
  - application intent handlers added under `application/use_cases/intents`.
- [x] Removed reflection-style probing/dispatch globally in runtime code:
  - zero `respond_to?(` occurrences.
  - zero `public_send` occurrences.
  - zero dynamic `send(` occurrences.
- [x] Removed collaborator-probing rescues:
  - zero `rescue NoMethodError` collaborator probing occurrences.
- [x] Removed known swallow/fallback runtime behaviors in strict paths:
  - annotation refresh now fails fast.
  - reader quit/save progress now fails fast.
  - event bus subscriber failures are logged then re-raised.
  - render state writer failures are logged then re-raised.
  - document path resolver no longer masks resolver failures.
  - kitty image line renderer no longer suppresses renderer exceptions.
- [x] Removed known mechanical migration violations:
  - bare `rescue =>` patterns removed (runtime code).
  - inline `... rescue ...` expressions removed from runtime code.
- [x] Boundary translation hardened:
  - document load failures are translated to `Shoko::BookParseError`.
  - dictionary catalog boundary uses typed `CatalogError < Shoko::Error`.
  - cache import boundary uses typed `ImportError < Shoko::Error`.
- [x] Completed inbound handler decoupling from adapter controllers:
  - application intent handlers now depend on typed executors (`ReaderIntentExecutor` / `MenuIntentExecutor`).
  - adapter controller dispatch moved to adapter bridges.
  - no `@reader_controller.` / `@menu_controller.` loopback remains in app intent handlers.
- [x] Replaced bootstrap session contexts with launch-state ports/adapters:
  - added `Core::Ports::Outbound::ReaderLaunchState` and `MenuLaunchState`.
  - runtime adapters added in `adapters/runtime/session_state`.
  - `ReaderSessionContext` / `MenuSessionContext` removed from bootstrap.
  - application workflows and unified app now use launch-state ports.
- [x] Enforced symbol-only input command execution contract:
  - `Adapters::Input::Commands.execute` now rejects non-symbol commands.
  - legacy proc/object/array execution paths removed.
- [x] Optional dependency hard-error path introduced for sqlite execution:
  - added `Shared::OptionalDependency.require_gem!`.
  - added `DependencyUnavailableError` and used it in sqlite runtime load path.
  - dictionary repository now remains wired in auto mode; missing sqlite fails explicitly on invocation.
- [x] Fixed reader relaunch crash after closing/opening another book:
  - reader launch state now clears background worker on reader exit (`RuntimeExecution#run_reader` ensure block), preventing reuse of stopped workers.
- [x] Added canonical zero-fallback architecture guardrails:
  - `spec/core/architecture/no_rescue_literal_default_spec.rb`
  - `spec/core/architecture/no_overlapping_rescue_chains_spec.rb`
  - `spec/core/architecture/no_stale_optional_resolution_spec.rb`
  - `spec/core/architecture/no_standard_error_rescue_spec.rb`
- [x] Completed zero-fallback sweep for `rescue -> literal default` patterns (`nil/false/[]/{}/''/""/:symbol`) in runtime code.
  - heuristic sweep count is now `0` occurrences in `lib/shoko/**`.
- [x] Removed duplicate/overlapping rescue chains that created unreachable branches.
  - importer translation chains fixed (`fb2`, `kindle`, `pdf`, `rtf`).
  - cache/string translation chain fixed (`lazy_file_string`).
  - CLI contract coercion rescue overlaps fixed.
  - bootstrap background worker fallback contract rescue overlap fixed.
- [x] Removed stale optional-resolution scaffolding in reader composition.
  - `ReaderBuilder#resolve_many` now has a single deterministic resolve path.
- [x] Eliminated explicit `rescue StandardError` usage in `lib/shoko/**`.
  - fail-fast boundaries now use explicit/translated rescue flows without `rescue StandardError`.

## Open Items

- [ ] Persist benchmark baselines and enforce CI threshold checks.
- [ ] Fixture lane is blocked locally by missing required books (see verification snapshot).
- [ ] Extend optional dependency hard-error semantics to remaining optional capability execution paths (not only sqlite).

## Verification Checklist

- [x] `bundle exec rspec spec/core/architecture spec/bootstrap/dependencies`
- [x] `bundle exec rake test:guardrails`
- [x] `bundle exec rake test:required`
- [x] `bundle exec rspec`
- [ ] `bundle exec rake test:fixtures` (blocked locally)

## Verification Snapshot

- `bundle exec rspec spec/core/architecture spec/bootstrap/dependencies`:
  - 90 examples, 0 failures.
- `bundle exec rake test:guardrails`:
  - pass.
- `bundle exec rake test:required`:
  - pass for seeds `10101`, `20202`, `30303`.
- `bundle exec rspec`:
  - 952 examples, 0 failures.
- `bundle exec rake test:fixtures`:
  - blocked by missing files:
    - `Persuasion (Jane Austen).mobi`
    - `Pride Prejudice (Jane Austen).azw`
    - `Emma (Jane Austen).azw3`
    - `Pride And Prejudice (Austen Jane).rtf`
- Artifact sweeps (`lib/shoko`):
  - `resolve_optional(`: `0`
  - `rescue StandardError`: `0`
  - bare `rescue =>`: `0`
  - duplicate `rescue ArgumentError, ArgumentError`: `0`
  - duplicate/overlapping same-class rescue chains with unreachable fallback branches: `0`
  - stale optional resolution ternary (`optional ? resolve : resolve`): `0`
  - inline `... rescue ...` expressions: `0`
  - `rescue NoMethodError` probing: `0`
  - `respond_to?` / `public_send` / dynamic `send(`: `0`
  - heuristic `rescue -> literal default` patterns: `0`
