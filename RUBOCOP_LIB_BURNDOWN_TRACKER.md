# RuboCop `lib/shoko` Burn-Down Tracker

Date: 2026-03-05  
Scope: `lib/shoko` only  
Owner lane: `bundle exec rubocop lib/shoko`  
End state: remove `.rubocop_todo.yml` completely

## Goal
- Eliminate RuboCop debt in `lib/shoko` under current strict limits.
- Keep architecture/cohesion intact while refactoring.
- Reach zero `lib/shoko` offenses without baseline suppression files.

## Locked Rules (No Shortcuts)
- No new `Exclude` entries for `lib/shoko` in `.rubocop.yml`.
- No new global cop-limit loosening in `.rubocop.yml`.
- No new permanent `rubocop:disable` in `lib/shoko` without explicit tracker justification and removal follow-up.
- Complex hotspots must be refactored, not hidden.
- `.rubocop_todo.yml` must be deleted at completion.

## Canonical Commands
- Strict report (ignores todo): `ruby script/quality/rubocop_lib_strict_report.rb`
- Enforced lane: `bundle exec rubocop lib/shoko`
- Optional full visibility run: `bundle exec rubocop`
- Guardrails: `bundle exec rake test:guardrails`
- Required deterministic non-fixture lane: `bundle exec rake test:required`
- Fixture lane (when available): `SHOKO_BOOK_FIXTURES=1 bundle exec rake test:fixtures`

## Baseline Snapshot (Strict, No Todo)
- Captured: 2026-03-05
- Inspected files: 583
- Files with offenses: 310
- Total offenses: 1829
- Cops with offenses: 119

### Top Offending Cops
| Cop | Offenses |
| --- | ---: |
| `Metrics/MethodLength` | 289 |
| `Metrics/AbcSize` | 247 |
| `Metrics/CyclomaticComplexity` | 130 |
| `Layout/LineLength` | 99 |
| `Metrics/PerceivedComplexity` | 93 |
| `Style/RedundantStructKeywordInit` | 79 |
| `Style/IfUnlessModifier` | 69 |
| `Metrics/ParameterLists` | 58 |
| `Layout/IndentationWidth` | 52 |
| `Metrics/ClassLength` | 40 |

### Top Offending Files
| File | Offenses |
| --- | ---: |
| `lib/shoko/core/book_formats/rtf/rtf_parser.rb` | 87 |
| `lib/shoko/core/book_formats/pdf/pdf_content_parser.rb` | 57 |
| `lib/shoko/core/book_formats/pdf/pdf_text_extractor.rb` | 55 |
| `lib/shoko/core/book_formats/pdf/pdf_reader.rb` | 45 |
| `lib/shoko/adapters/ui/sessions/dictionary_ui_session_adapter.rb` | 44 |
| `lib/shoko/adapters/ui/sessions/annotation_overlay_ui_session_adapter.rb` | 31 |
| `lib/shoko/adapters/output/formatting/formatting_service/line_assembler/table_renderer.rb` | 29 |
| `lib/shoko/adapters/ui/components/in_book_search_popup_component.rb` | 29 |
| `lib/shoko/adapters/ui/components/dictionary_popup/setup_flow.rb` | 27 |
| `lib/shoko/adapters/book_sources/kindle/kindle_importer.rb` | 26 |

## Progress Log
| Date | Batch | Before | After | Delta | Notes |
| --- | --- | ---: | ---: | ---: | --- |
| 2026-03-05 | Baseline capture | 1829 | 1829 | 0 | Strict no-todo baseline measured |
| 2026-03-05 | Batch 1 (safe autocorrect) | 1829 | 1589 | -240 | Layout/alignment/trailing comma/empty-line/if-modifier cleanup |
| 2026-03-05 | Batch 2 (focused style autocorrect) | 1589 | 1454 | -135 | `RedundantStructKeywordInit`, `NumericPredicate`, `ReduceToHash`, `InverseMethods`, `ArgumentsForwarding` |
| 2026-03-05 | Batch 3 (lane stabilization fixes) | 1454 | 1446 | -8 | Repaired new direct lane offenses introduced during autocorrect |
| 2026-03-05 | Batch 4 (broader style/lint autocorrect) | 1446 | 1354 | -92 | Safe-navigation/regex/guard/parentheses/layout cleanup sweep |
| 2026-03-05 | Batch 5 (semantic rollback + guardrail recovery) | 1354 | 1295 | -59 | Restored boolean semantics, removed rescue literal defaults, kept lane clean |
| 2026-03-05 | Batch 6 (line-length/style quick-win sweep) | 1295 | 1247 | -48 | Reduced `Layout/LineLength` and related style debt while keeping lane green |
| 2026-03-05 | Batch 7 (manual metrics refactor: table_renderer) | 1247 | 1220 | -27 | Reduced `table_renderer.rb` from 28 strict offenses to 1 (`ClassLength`) |

Current strict no-todo offense count: **1220**

## Batch Checklist
- [x] Phase 0: tracker + strict-report plumbing.
- [x] Phase 1: enforce `lib/shoko` RuboCop lane in `Rakefile` and keep optional full run.
- [x] Phase 2: low-risk safe autocorrect batches with per-batch regression checks.
- [ ] Phase 3A: adapter/UI cluster metrics refactors.
- [ ] Phase 3B: importer cluster metrics refactors.
- [ ] Phase 3C: parser cluster metrics refactors (`rtf_parser`, PDF stack).
- [ ] Phase 3D: core service/pagination metrics refactors.
- [ ] Phase 4: line-length cleanup to 120 without limit changes.
- [ ] Phase 5: delete `.rubocop_todo.yml` after strict zero-offense confirmation.

## Milestones
- [x] M1: tracker + strict reporting + lane wiring.
- [x] M2: low-risk debt significantly reduced.
- [ ] M3: adapter/importer metrics debt mostly cleared.
- [ ] M4: parser/service metrics debt cleared.
- [ ] M5: `.rubocop_todo.yml` removed and `lib/shoko` strict lane clean.

## No-Regression Verification Checklist
- [ ] `bundle exec rubocop lib/shoko` passes with no `.rubocop_todo.yml`.
- [x] `bundle exec rake test:guardrails`.
- [x] `bundle exec rake test:required`.
- [x] `SHOKO_BOOK_FIXTURES=1 bundle exec rake test:fixtures` (when fixture env available).
