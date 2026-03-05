# LIB Remediation Tracker

Date: 2026-03-05
Scope: `lib/` audit findings from `LIB_AUDIT_REPORT.md` + remediation work completed afterward.

## Goal
- Keep `lib/shoko` aligned with strict hexagonal architecture boundaries.
- Eliminate correctness defects and unjustified legacy rescue patterns.
- Keep regressions permanently blocked with architecture guardrails + solid tests.

## Status Summary
- Audit high-severity findings: **addressed**.
- Audit medium/low structural maintainability items: **in progress with parser/bootstrap slices 0/1/2/3/4/5/6 + parser completion (P1/P2) + UI continuation (7A/7B) completed**.
- Verification lanes: **green** (`guardrails`, `required`, `fixtures`, `rubocop lib/shoko`).

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
- [x] **Slice 0 baseline/safety harness expansion completed**
  - Expanded PDF extractor characterization coverage (`Tf`, `Tj`, `TJ`, `Td`, `Tm`, `T*`, malformed/nested token resilience).
  - Expanded PDF reader coverage (traditional xref + xref stream entry parsing).
  - Added dedicated PDF importer extraction-flow spec (`spec/adapters/book_sources/pdf/pdf_importer_spec.rb`).
  - Expanded RTF parser edge-case coverage (dispatch/destination/truncated-escape resilience).
- [x] **Slice 1/2 PDF extractor internal refactor completed**
  - Introduced internal collaborators:
    - `PdfContentStreamParser`
    - `PdfContentStreamTokenizer`
    - `PdfTextFragmentDecoder`
    - `PdfFontProfileResolver`
  - `PdfTextExtractor` now delegates stream parsing and font-resource/profile resolution to focused helpers.
  - Added inherited-resources and FontDescriptor italic-angle coverage.
- [x] **Slice 3 PDF content parser decomposition completed**
  - Introduced layout collaborators:
    - `PdfLayoutPayloadParser`
    - `PdfLayoutLineNormalizer`
    - `PdfLayoutHeuristics`
    - `PdfLayoutGroupBuilder`
    - thin `PdfLayoutClassifier` facade
  - Preserved fallback behavior for malformed layout payloads and plain-text paragraphs.
  - `pdf_content_parser.rb` strict offenses reduced **39 -> 0**.
- [x] **Slice 4 RTF parser dispatcher/state decomposition completed**
  - Split parser concerns into focused collaborators:
    - `RtfParserGroupHandlers`
    - `RtfParserControlDispatcher`
    - `RtfParserControlActions`
    - `RtfParserByteHandlers`
    - `RtfParserOutputHelpers`
  - Replaced reflection-style dispatch with callable handler maps (`Method#call`) to satisfy strict architecture guardrails.
  - Preserved malformed unicode/hex skip behavior and destination skipping semantics.
  - `rtf_parser.rb` strict offenses reduced **39 -> 0**.
- [x] **PDF importer layout normalization correctness tightened**
  - `normalize_layout_line` now preserves explicit `false` boolean values (e.g., `italic: false`) rather than collapsing to nil.
- [x] **Slice 5 dependency bundle structural cleanup completed**
  - `ReaderControllerDependencies` bundle constants/types moved out of `Data.define` block scope.
  - `Lint/ConstantDefinitionInBlock` debt reduced significantly in strict mode.
- [x] **Slice 6 composition root decomposition completed**
  - `domain_application_registration.rb` split into focused registration helper methods by role.
  - Added bootstrap registration contract spec:
    - `spec/bootstrap/domain_application_registration_spec.rb`
- [x] **Slice P1/P2 parser-completion completed (`pdf_reader` + `pdf_importer`)**
  - Added PDF reader collaborators:
    - `Reader::XrefTableParser`
    - `Reader::XrefStreamParser`
    - `Reader::StreamLengthResolver`
  - Added PDF importer collaborators:
    - `Importer::MetadataNormalizer`
    - `Importer::PageExtractionCoordinator`
  - Expanded parser/importer coverage:
    - `spec/core/book_formats/pdf/pdf_reader_spec.rb`
    - `spec/adapters/book_sources/pdf/pdf_importer_spec.rb`
  - Parser ingestion hotspot debt moved **42 -> 4** (`pdf_reader`: `24 -> 1`, `pdf_importer`: `18 -> 3`).
- [x] **Slice 7A/7B UI continuation completed (target quartet)**
  - Refactored context-driven rendering and helper segmentation in:
    - `in_book_search_popup_component.rb` (`29 -> 1`)
    - `dictionary_popup/setup_flow.rb` (`25 -> 1`)
    - `annotation_editor_overlay_component.rb` (`18 -> 1`)
    - `annotation_markup.rb` (`22 -> 14`)
  - Added focused collaborator for marker pairing:
    - `ui/annotation_markup/pair_finder.rb`
  - Added dedicated annotation editor component spec:
    - `spec/adapters/ui/components/annotation_editor_overlay_component_spec.rb`
- [x] **Parser close-out + annotation markup completion completed**
  - `pdf_text_extractor.rb` reduced **5 -> 0** via paragraph/layout helper extraction.
  - `pdf_reader.rb` reduced **1 -> 0** by extracting dictionary-value parsing into `Reader::DictionaryValueParser`.
  - `pdf_importer.rb` reduced **3 -> 0** by moving BookData/TOC helpers into `Importer::BookDataHelpers`.
  - `annotation_markup.rb` reduced **14 -> 0** by splitting traversal logic into:
    - `ui/annotation_markup/render_engine.rb`
    - `ui/annotation_markup/cursor_position_engine.rb`
    - `ui/annotation_markup/cursor_map_builder.rb`
    - `ui/annotation_markup/style_support.rb`
- [x] **Enhanced popup menu structural decomposition completed**
  - `enhanced_popup_menu.rb` reduced **15 -> 0** by splitting positioning and rendering concerns into:
    - `components/enhanced_popup_menu/positioning_helpers.rb`
    - `components/enhanced_popup_menu/render_helpers.rb`
  - Initializer contract tightened to keyword-driven dependencies while preserving component factory behavior.
  - Added/updated focused spec coverage:
    - `spec/adapters/ui/components/enhanced_popup_menu_spec.rb`
- [x] **Strict RuboCop debt reduced in this session**
  - Strict no-todo count moved **1220 -> 928** (`-292`).
  - Parser hotspot subtotal (`pdf_content_parser`, `rtf_parser`, `pdf_text_extractor`, `pdf_reader`, `pdf_importer`) moved **154 -> 0**.
  - Target files now at:
    - `pdf_content_parser.rb`: 0
    - `rtf_parser.rb`: 0
    - `pdf_text_extractor.rb`: 0
    - `pdf_reader.rb`: 0
    - `pdf_importer.rb`: 0

## Pending / Not Yet Done
- [ ] **Audit medium-priority structural refactors are still open**
  - Split very large parser/modules to reduce complexity and improve maintainability velocity.
  - Continue composition-root concentration reduction in remaining bootstrap registration modules.
- [ ] **RuboCop strict debt burn-down (`lib/shoko`) is in progress**
  - Current strict no-todo count is **928** offenses (down from 1829 baseline).
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
  spec/adapters/book_sources/pdf/pdf_importer_spec.rb \
  spec/core/book_formats/pdf/pdf_content_parser_spec.rb \
  spec/core/book_formats/pdf/pdf_text_extractor_spec.rb \
  spec/core/book_formats/pdf/pdf_reader_spec.rb \
  spec/core/book_formats/rtf/rtf_parser_spec.rb \
  spec/adapters/ui/components/in_book_search_popup_component_spec.rb \
  spec/adapters/ui/components/dictionary_popup_component_spec.rb \
  spec/adapters/ui/components/ui/annotation_markup_spec.rb \
  spec/adapters/ui/components/annotation_editor_overlay_component_spec.rb \
  spec/core/architecture/no_noop_reraise_rescue_spec.rb \
  spec/adapters/output/formatting/wrapping_service_spec.rb \
  spec/bootstrap/domain_application_registration_spec.rb

ruby script/architecture/fallback_report.rb
bundle exec rake test:guardrails
bundle exec rake test:required
ruby script/quality/rubocop_lib_strict_report.rb
bundle exec rubocop lib/shoko
SHOKO_BOOK_FIXTURES=1 bundle exec rake test:fixtures
```
