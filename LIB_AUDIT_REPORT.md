# `lib/` Deep Audit Report

Date: 2026-03-05
Scope: **Only `lib/`** (no docs/readme claims used)

## 1. Scope Confirmation

I scanned the full `lib/` tree recursively and processed **every file**:

- Total files: **586**
- Ruby files: **584**
- Non-Ruby files: **2**
  - `lib/shoko/shared/terminal/kitty_unicode_placeholders_diacritic_codepoints.txt`
  - `lib/shoko/shared/unicode_display_width/display_width.marshal.gz`
- Total lines: **66,592**

A full file manifest is attached in `LIB_AUDIT_FILE_MANIFEST.md`.

## 2. Overall Rating (1-10)

**7.8 / 10**

Interpretation:
- High sophistication in architecture layering, custom parsing infrastructure, and no-runtime-gem strategy.
- Score is pulled down by concrete correctness defects in error handling and by maintainability drag from very large, high-complexity files.

## 3. Hexagonal Architecture Verdict

**Verdict: mostly true, and mostly clean.**

### What is clean
- Layering is explicit and consistent: `core`, `application`, `adapters`, `bootstrap`, `shared`.
- No forbidden dependency direction was found in `require_relative` edges.
- No forbidden constant-reference direction was found (`core`/`application` do not reach into `adapters`/`bootstrap`).

Dependency edge summary (`require_relative` counts):
- `core -> adapters/application/bootstrap`: **0**
- `application -> adapters/bootstrap`: **0**
- `shared -> core/application/adapters/bootstrap`: **0**

### One architecture leak
- `lib/shoko/adapters/output/formatting/wrapping_service.rb:176` reaches into `Shoko::Core::Services::Pagination::Internal::ChapterCache` (an internal core implementation detail, not a port).
- This is small, but it weakens strict boundary discipline.

## 4. Strong Points

- Strong consistency: `# frozen_string_literal: true` in **100%** of Ruby files.
- No runtime third-party gem dependency in the core runtime path (only stdlib; `rspec/mocks` is test-container scoped).
- Good defensive infrastructure in several places:
  - atomic file writes (`AtomicFileWriter`)
  - zip decompression limits (`zip_reader`)
  - text/ANSI/XML sanitization (`TextSanitizer`)
- Sophisticated custom parsers for EPUB/PDF/RTF/FB2/Kindle without gem-heavy runtime dependencies.

## 5. Findings (Severity-Ordered)

## HIGH

### H1) File descriptor leak risk in ZIP reader error path

- `lib/shoko/adapters/book_sources/archive/zip_reader.rb:660-662`
- `Zip::File#initialize` rescues `Shoko::Error` only.
- But malformed zip failures are raised as `Zip::Error` (not `Shoko::Error`), so `close` is skipped on failure.

Why this matters:
- Repeated failed opens can accumulate open descriptors until GC runs.

Confirmed behavior:
- Repeated invalid opens increased FD count from `13` to `113` before GC, then dropped after GC.
- This is a real operational leak pattern under sustained malformed-input traffic.

### H2) `PdfContentParser` fallback path is not actually reliable for malformed JSON/layout payloads

- `lib/shoko/core/book_formats/pdf/pdf_content_parser.rb:39-42`
- `parse` rescues `Shoko::Error` only.
- `parse_json_payload` uses `JSON.parse` (`:511`) and `parse_float` uses `Float(value)` (`:679`), both can raise stdlib exceptions (`JSON::ParserError`, `ArgumentError`, `TypeError`) that are **not** `Shoko::Error`.

Impact:
- Instead of graceful fallback blocks, parser can hard-fail on malformed inputs.

Confirmed behavior:
- Malformed JSON-like text raised `JSON::ParserError`.
- Invalid numeric `x` value raised `ArgumentError: invalid value for Float()`.

### H3) `RtfParser` has incorrect rescue class for malformed unicode/encoding paths

- `lib/shoko/core/book_formats/rtf/rtf_parser.rb:320-322`
- `lib/shoko/core/book_formats/rtf/rtf_parser.rb:580-582`
- `lib/shoko/core/book_formats/rtf/rtf_parser.rb:617-622`

Comments claim malformed unicode/hex should be skipped, but rescues are `Shoko::Error` in paths that throw stdlib encoding/range exceptions.

Confirmed behavior:
- Crafted malformed `\u` payload raised encoding exception instead of being skipped.

## MEDIUM

### M1) Excessive rescue/re-raise boilerplate introduces noise and masking risk

- `rescue Shoko::Error` occurrences: **327**
- Redundant immediate re-raise pattern count: **126**

Why this matters:
- Increases cognitive load.
- Encourages accidental wrong rescue class usage (seen in High findings).
- Makes meaningful exception boundaries harder to reason about.

### M2) Several files are too large/high-complexity for maintainability

Top examples:
- `lib/shoko/core/book_formats/epub/xhtml_content_parser.rb` (803 lines)
- `lib/shoko/core/book_formats/rtf/rtf_parser.rb` (767)
- `lib/shoko/adapters/book_sources/archive/zip_reader.rb` (746)
- `lib/shoko/core/book_formats/pdf/pdf_content_parser.rb` (687)
- `lib/shoko/core/book_formats/pdf/pdf_text_extractor.rb` (629)

This is understandable given the “no runtime gems” objective, but these modules are now hard to evolve safely without stronger internal segmentation/tests.

### M3) Composition root is highly centralized and heavy

- `lib/shoko/bootstrap/container_factory/domain_application_registration.rb` (340 lines)
- `lib/shoko/bootstrap/container_factory/port_and_repository_registration.rb` (231)

Large manual wiring is expected in strict DI, but current size makes dependency drift and subtle config bugs more likely.

## LOW

### L1) ZIP reader does not appear to validate CRC

- `lib/shoko/adapters/book_sources/archive/zip_reader.rb`
- Good size-limit protections exist, but CRC integrity verification is not obvious/present.

Impact:
- Corruption detection is weaker than it could be.

## 6. Overengineering / Redundancy Notes

Given your explicit no-runtime-gems constraint, a lot of complexity is justified.

Still, these areas are likely over-abstracted for current value:
- High number of tiny bridge/adapter wrappers that mostly pass-through.
- Very large intent dispatch maps in bridge classes (`reader/menu intent executor bridges`) that create boilerplate synchronization burden.

This is not “bad architecture”, but it increases maintenance cost significantly.

## 7. Coding Style Assessment

Style quality: **good overall**

- Consistent namespacing and module organization.
- Good use of immutable constants and structured value objects.
- Defensive argument/type checks are frequent.

Main style weakness:
- Exception handling style is inconsistent in quality (some very good boundary translation; some redundant; some incorrect class selection).

## 8. Priority Fix Plan

1. **Fix incorrect rescue classes in parser/zip hotspots first**
   - `pdf_content_parser.rb`, `rtf_parser.rb`, `zip_reader.rb`
2. **Eliminate redundant `rescue Shoko::Error; raise` patterns**
   - Keep only boundary translations/logging that add value.
3. **Split monolith parser files into smaller internal collaborators**
   - Preserve behavior, improve testability and patch velocity.
4. **Add corruption/integrity coverage where missing**
   - ZIP CRC checks (or explicit decision not to support, documented in code comments).
5. **Guard architecture strictness with lightweight automated checks**
   - Prevent future internal-core leakage from adapters.

## 9. Bottom Line

This is a genuinely sophisticated codebase, especially under a strict no-runtime-gems constraint and with heavy parsing/rendering concerns.

The biggest non-excusable issues are **error-handling correctness defects** (not just style), because they can cause hard failures and resource leaks exactly in malformed-input scenarios where robustness matters most.
