# Shoko Full Codebase Audit (2026-03-05)

## Scope and Coverage Proof
- Audit scope: **every tracked file** in repository (`lib`, `bin`, `spec`, root, tracked fixtures/assets/tmp artifacts).
- Source of truth: `git ls-files -z`.
- Deterministic scan results:
  - total tracked files: **949**
  - scanned files: **949**
  - missing files: **0**
  - text files: **932**
  - binary/non-UTF8 files: **17**

### Coverage artifacts
- `tmp/full_repo_scan_manifest_2026-03-05.json`
- `tmp/full_repo_scan_files_2026-03-05.txt`
- `tmp/ui_theming_evidence_matrix_2026-03-05.json`

## UI/UX + Theming Evidence Matrix
Keyword-driven UI/theming/responsive discovery was classified into:
- `must_unify`: 6
- `intentional_divergence`: 3
- `non-UI/no-action`: 310
- matched files total: 319

### Must-unify targets (implemented in this pass)
- `lib/shoko/adapters/ui/components/dictionary_popup_component.rb`
- `lib/shoko/adapters/ui/components/in_book_search_popup_component.rb`
- `lib/shoko/adapters/ui/components/annotation_editor_overlay_component.rb`
- `lib/shoko/adapters/ui/components/dictionary_panel_component.rb`
- `lib/shoko/adapters/ui/constants/ui_constants.rb`
- `lib/shoko/adapters/ui/constants/themes.rb`

## Remediation Delivered

### Theme correctness and canonicalization
- Added canonical theme normalization and legacy alias handling (`dark -> default`, `light -> gray`).
- Config theme load/update paths now normalize and persist canonical IDs.
- Initial default theme corrected to canonical `:default`.

### Theme context unification
- Introduced `ThemeContext` as canonical runtime object:
  - `theme_id`
  - derived `color_mode`
  - resolved palette
  - resolved UI token snapshot
- Reader palette and UI color mode application now flow through this context.

### Settings UX and controls
- Added user-facing theme control in Settings menu (`Theme`).
- Added `SettingsService#cycle_theme` and `SettingsService#set_theme` with validation.
- Wired menu action dispatch for theme cycling.

### Live theme propagation
- `ComponentFactory` now resolves theme dynamically from current config instead of one-time startup mode.
- Added runtime refresh hooks so active cached components update color mode in place:
  - dictionary session components
  - in-book search popup
  - annotation editor overlay

### UI/UX coherence fixes
- Fixed browse search-active styling logic regression (`search_active?` now respected correctly).
- Unified dictionary panel formatter color-mode path (was previously defaulting inconsistently).
- Removed dead header theme parameter that was not used.

### Runtime dependency policy guard
- Added contract test ensuring **no runtime gem dependencies** are declared in gemspec.

## Validation Results
- Targeted remediation specs: **66 examples, 0 failures**
- Full non-fixture suite: **1058 examples, 0 failures**
- RuboCop on all changed Ruby files: **0 offenses**

## Notes on Intentional Divergence
Some UI differences remain intentional (context-specific behavior):
- annotation edit/detail views versus list-oriented screens
- metadata-heavy library details panel layout

These are retained by design, not accidental inconsistency.
