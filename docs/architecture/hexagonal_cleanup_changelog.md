# Hexagonal Cleanup Changelog

## Removed Runtime Artifacts

- `Shoko::Core::Ports::CommandPort`
  - Replacement: `Shoko::Application::Ports::CommandPort`
- `Shoko::Adapters::Runtime::RuntimeConfigProvider`
  - Replacement: explicit `runtime_config` injection from composition
- `lib/shoko/internal/zip_reader.rb`
  - Replacement: `lib/shoko/adapters/book_sources/archive/zip_reader.rb`
- `lib/zip.rb`
  - Replacement: adapter-owned archive access via `Shoko::Adapters::BookSources::Archive::ZipReader`
- `Shoko::EPUBParseError`
  - Replacement: `Shoko::BookParseError`
- `Shoko::Adapters::Monitoring::Logger`
  - Replacement: injected `Shoko::Adapters::Monitoring::LoggerAdapter`
- `lib/shoko/application/dependency_container.rb`
  - Replacement: `lib/shoko/application/composition/dependency_container.rb`

## Renames

- `Shoko::Application::Ports::UIComponentFactory` -> `Shoko::Application::Ports::UiComponentFactory`
- `Shoko::Adapters::State::UIStateReaderAdapter` -> `Shoko::Adapters::State::UiStateReaderAdapter`
- Application/UI runtime namespace normalization: `Application::UI` -> `Application::Ui`
- Adapter UI helper namespace normalization: `...::UI` -> `...::Ui`

## Pagination Boundary Refactor

- `Shoko::Core::Services::PageCalculatorService`
  - Removed constructor dependency on UI state readers
  - Hydration now accepts explicit layout inputs (`width`, `height`, `sidebar_visible`)
- `Shoko::Core::Services::Pagination::Internal::LayoutMetricsCalculator`
  - Layout calculations are input-driven (no UI-state reader dependency)
- `Shoko::Core::Services::Pagination::Internal::PageHydrator`
  - Hydration receives explicit layout dimensions

## Runtime Config Boundary Updates

- ZIP limits now flow through `Core::Ports::RuntimeConfig`:
  - `zip_max_entry_uncompressed_bytes`
  - `zip_max_entry_compressed_bytes`
  - `zip_max_total_uncompressed_bytes`
- `EnvRuntimeConfigAdapter` and `NullRuntimeConfig` implement ZIP limit accessors.
- ZIP reader no longer reads process `ENV` directly.

## Migration Path

- Added `bin/migrate-v2` (backup, JSON normalization, cache purge, marker write).
- Added `bin/migrate-v2-rollback` (restore latest backup, clear cache).
- Added startup migration preflight gate:
  - `Shoko::Application::Composition::Bootstrap::MigrationPreflight`
