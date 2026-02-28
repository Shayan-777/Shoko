# Hexagonal Architecture Adherence Checklist (Strict)

Date: 2026-02-28
Scope: full repository scan (`lib/`, `spec/`, bootstrap wiring, architecture guardrails)

## Completed

- [x] Reader runtime orchestration lives in adapter-layer reader runtime classes.
- [x] Application startup/menu dispatch uses an explicit app mode runner boundary.
- [x] Terminal lifecycle access in application startup uses a terminal session port.
- [x] Pending jump editor launch uses a dedicated outbound launcher port.
- [x] Session result contract is shared (`shared/contracts`) and used across adapters.
- [x] Deprecated UI-shaped menu/overlay outbound contracts were removed from core.
- [x] Menu state controller now has a minimal dependency set and delegates to precomposed workflows.
- [x] Reader launch flow was split into dedicated collaborators:
  - Path resolution
  - Document preparation
  - Runtime execution
  - Progress orchestration
- [x] Domain event metadata creation is port-driven through an event factory.
- [x] New runtime ports/adapters added and wired:
  - Terminal session
  - App mode runner
  - Annotation editor launcher
  - Wall clock
  - Id generator
- [x] Architecture guardrails expanded for:
  - Application controller-runtime API coupling
  - Application terminal dependency leakage
  - Cross-adapter input-to-ui constant coupling
  - Tombstone artifacts and legacy reference reintroduction

## Verification Checklist

- [x] `bundle exec rspec spec/core/architecture`
- [x] `bundle exec rspec spec/bootstrap/dependencies`
- [x] `bundle exec rake test:guardrails`
- [x] `bundle exec rake test:required`
- [x] `bundle exec rspec`
- [x] Full-suite random-seed reruns (10 random + fixed seeds `10101`, `20202`, `30303`)
- [x] Performance sanity checks for menu/reader startup paths

### Verification Snapshot

- `bundle exec rspec spec/core/architecture`: 60 examples, 0 failures.
- `bundle exec rspec spec/bootstrap/dependencies`: 8 examples, 0 failures.
- `bundle exec rake test:guardrails`: pass.
- `bundle exec rake test:required`: pass.
- `bundle exec rspec`: 895 examples, 0 failures.
- Full-suite seed stability (`bundle exec rspec --seed`): passed for
  `56072 52407 49446 61968 63851 1559 87095 97342 65033 5517 10101 20202 30303`.
- Final zero-legacy sweep for removed contracts/artifacts (excluding intentional tombstone guardrail specs): pass.

### Performance Snapshot

- `script/bench/startup_menu_benchmark.rb`:
  - `require_ms` mean `264.65`
  - `run_ms` mean `71.77`
  - `total_ms` mean `336.44`
- `script/bench/sidebar_toggle_layout_benchmark.rb`:
  - Baseline rebuild: `7429.22 ms`
  - Optimized variant switch: `1.92 ms`
  - Speedup: `3873.40x`
- `script/bench/snappiness_benchmark.rb`:
  - Broad cache/path improvements across most scenarios
  - One scenario slower (`WrappingService.wrap_window prefetch reuse`: `0.83x`)

Note: repository benchmarks currently do not persist historical pre-refactor baselines, so strict pre/post `% regression` enforcement is not automated yet.

## Remaining Work

- [ ] Optional: add persisted benchmark baseline artifacts + CI threshold checks for automatic `>10%` regression detection.
