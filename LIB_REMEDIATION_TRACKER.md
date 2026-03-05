# LIB Remediation Tracker

Date: 2026-03-05
Scope: `lib/` audit findings from `LIB_AUDIT_REPORT.md` + remediation work completed afterward.

## Goal
- Keep `lib/shoko` aligned with strict hexagonal architecture boundaries.
- Eliminate correctness defects and unjustified legacy rescue patterns.
- Keep regressions permanently blocked with architecture guardrails + solid tests.

## Status Summary
- Audit high-severity findings: **addressed**.
- Audit medium/low structural maintainability items: **partially addressed**.
- Verification lanes: **mostly green** (see pending items).

## Completed
- [x] **H1 ZIP resource-safety defect fixed**
  - `Zip::File` initialization failure path now performs cleanup reliably.
  - Invalid archive open loops no longer leave descriptor growth behavior.
- [x] **ZIP integrity hardening implemented**
  - Added CRC metadata propagation and strict CRC mismatch rejection.
- [x] **H2 PDF malformed-input resilience fixed**
  - Malformed JSON/layout and invalid float alignment inputs now follow fallback paths without uncaught stdlib exceptions.
- [x] **H3 RTF malformed unicode/hex resilience fixed**
  - Parser now skips malformed unicode/hex tokens safely and continues.
- [x] **Adapter -> core internal coupling leak removed**
  - `WrappingService` no longer directly constructs `Core::Services::Pagination::Internal::ChapterCache`.
  - Cache factory is injected and wired from bootstrap composition root.
- [x] **No-op rescue legacy cleanup completed (full sweep)**
  - No remaining no-op `rescue ...; raise` offenders in `lib/shoko`.
- [x] **Architecture guardrail scope expanded to full `lib/shoko`**
  - `spec/core/architecture/no_noop_reraise_rescue_spec.rb`
  - `script/architecture/fallback_report.rb`
- [x] **RSpec coverage added/expanded for remediated areas**
  - ZIP CRC + invalid archive behavior
  - PDF malformed payload resilience
  - RTF malformed unicode/hex resilience
  - WrappingService injected cache factory behavior
- [x] **Guardrail reports currently clean**
  - `fallback_report` summary currently reports all-zero offenders.
- [x] **Core deterministic lanes pass**
  - Targeted remediation specs pass.
  - `bundle exec rake test:guardrails` passes.
  - `bundle exec rake test:required` passes.
- [x] **RuboCop remediation strategy finalized and tracked**
  - Burn-down now has a dedicated tracker: `RUBOCOP_LIB_BURNDOWN_TRACKER.md`.
  - Scope/goal locked to `lib/shoko` strict cleanup without permanent baseline suppression.
- [x] **Fixture lane unblocked using `testbooks/`**
  - Fixture root now defaults to `testbooks/` in `spec/spec_helper.rb`.
  - Kindle fixture specs now target the available MOBI/AZW/AZW3 files in `testbooks/`.
  - Added deterministic RTF fixture file: `testbooks/Pride And Prejudice (Austen Jane).rtf`.
  - `SHOKO_BOOK_FIXTURES=1 bundle exec rake test:fixtures` now passes.

## Pending / Not Yet Done
- [ ] **Audit medium-priority structural refactors are still open**
  - Split very large parser/modules to reduce complexity and improve maintainability velocity.
  - Reduce composition-root concentration in large bootstrap registration modules.
- [ ] **RuboCop strict debt burn-down (`lib/shoko`) is in progress**
  - Current strict no-todo count is 1220 offenses (down from 1829 baseline).
  - Completion criteria is tracked in `RUBOCOP_LIB_BURNDOWN_TRACKER.md` (including `.rubocop_todo.yml` deletion milestone).

## Current Definition of Done Check
- [x] Correctness defects identified in audit are remediated.
- [x] No-op rescue legacy patterns are removed from `lib/shoko` and guarded.
- [x] Hex-boundary leak identified in audit is removed.
- [x] Deterministic non-fixture regression lanes are passing.
- [x] Full RuboCop lane green.
- [x] Fixture lane green.

## Next Session Start Commands
Use these to quickly re-validate state in a new chat:

```bash
bundle exec rspec spec/adapters/book_sources/archive/zip_reader_entries_spec.rb \
  spec/core/book_formats/pdf/pdf_content_parser_spec.rb \
  spec/core/book_formats/rtf/rtf_parser_spec.rb \
  spec/core/architecture/no_noop_reraise_rescue_spec.rb \
  spec/adapters/output/formatting/wrapping_service_spec.rb

ruby script/architecture/fallback_report.rb
bundle exec rake test:guardrails
bundle exec rake test:required
bundle exec rubocop
SHOKO_BOOK_FIXTURES=1 bundle exec rake test:fixtures
```
