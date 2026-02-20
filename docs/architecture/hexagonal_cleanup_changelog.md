# Hexagonal Cleanup Changelog

## V4 Full Migration (Hard Cut)

### Layer and Root Reorganization

- Added top-level `presentation/ui` layer.
- Moved composition root from `application/composition` to top-level `bootstrap`.
- Moved application dependency bundles to `application/dependencies`.

### Runtime Session-State Migration

- Replaced `adapters/state/**` with `adapters/runtime/session_state/**`.
- Moved non-session adapters out of state bucket:
  - `adapters/output/layout/layout_metrics_adapter.rb`
  - `adapters/output/formatting/wrapped_lines_provider_adapter.rb`

### Presentation Migration

- Moved UI subtree:
  - `adapters/output/ui/**` -> `presentation/ui/**`
- Moved rendering models:
  - `adapters/output/rendering/models/**` -> `presentation/ui/rendering/models/**`
- Moved render registry:
  - `adapters/output/render_registry.rb` -> `presentation/ui/render_registry.rb`
- Renamed rendering factory adapter:
  - `presentation/ui/rendering_factory_adapter.rb` -> `presentation/ui/rendering_factory.rb`

### Rendering Ownership Consolidation

- Re-homed reading rendering files into:
  - `presentation/ui/rendering/views/**`
  - `presentation/ui/rendering/line/**`

### Namespace Hard-Cut Changes

- `Shoko::Application::Composition::*` -> `Shoko::Bootstrap::*`
- `Shoko::Application::Composition::Dependencies::*` -> `Shoko::Application::Dependencies::*`
- `Shoko::Adapters::State::*` -> `Shoko::Adapters::Runtime::SessionState::*`
- `Shoko::Adapters::Output::Ui::*` -> `Shoko::Presentation::Ui::*`
- `Shoko::Adapters::Output::Rendering::Models::*` -> `Shoko::Presentation::Ui::Rendering::Models::*`
- `Shoko::Adapters::Output::RenderRegistry` -> `Shoko::Presentation::Ui::RenderRegistry`

### Legacy Deletions Completed

- Removed legacy code trees:
  - `lib/shoko/application/composition/**`
  - `lib/shoko/adapters/state/**`
  - `lib/shoko/adapters/output/ui/**`
  - `lib/shoko/adapters/output/rendering/**`
  - `lib/shoko/application/main_menu/**`
- Removed all code references to:
  - `Application::Composition`
  - `Adapters::State`
  - `Adapters::Output::Ui`
  - `Adapters::Output::Rendering`

## V3 Big-Bang Cleanup

### Removed Contracts and Files

- Removed core-owned application contracts:
  - `lib/shoko/core/ports/config_reader.rb`
  - `lib/shoko/core/ports/reader_navigation_reader.rb`
  - `lib/shoko/core/ports/key_classifier.rb`
  - `lib/shoko/core/ports/notification_writer.rb`
  - `lib/shoko/core/ports/progress_state_reader.rb`
- Removed adapter and DI artifacts tied to legacy progress reader:
  - `lib/shoko/adapters/runtime/session_state/progress_state_reader_adapter.rb`
  - `:progress_state_reader` DI registration/resolution paths (runtime + test container)
- Removed dead state helper:
  - `set_nested` from `lib/shoko/adapters/runtime/session_state/state_store.rb`

### Port Ownership Migration

- Added application-owned ports:
  - `Application::Ports::ConfigReader`
  - `Application::Ports::ReaderNavigationReader`
  - `Application::Ports::KeyClassifier`
  - `Application::Ports::NotificationWriter`
- Updated adapters and consumers to use application-owned contracts.

### Core Purification

- `Core::Services::AnnotationService` no longer mutates reader state.
- Added `Application::Services::Reader::AnnotationStateService` wrapper to orchestrate
  persistence + reader annotation refresh writes.
- DI wiring now separates:
  - `:core_annotation_service` (pure core service)
  - `:annotation_service` (application orchestration wrapper)
- `Core::Services::PageCalculatorService` now returns payloads only.
- Pagination state writes were moved to application orchestrators/coordinators.

### Runtime Config Hook Removal

- Removed global runtime hook usage in composition runtime wiring.
- Replaced mutable setters with injected/thread-scoped runtime config usage for:
  - `TextMetrics`
  - `FormattingService::LineAssembler::Tokenizer`
  - terminal frame write path (`TerminalBuffer::Frame` / `TerminalBuffer` / `TerminalService`)
- Added `TextMetricsPortAdapter` to bridge core text metrics port with injected runtime config.

### Structural Reorganization

- Moved menu controller entrypoint:
  - `application/controllers/menu_controller.rb`
  - -> `application/controllers/menu/controller.rb`
- Moved menu action modules:
  - `application/controllers/menu_controller/*.rb`
  - -> `application/controllers/menu/actions/*.rb`
- Moved menu progress presenter:
  - `application/main_menu/menu_progress_presenter.rb`
  - -> `application/workflows/menu/menu_progress_presenter.rb`
- Renamed/moved reader input controller:
  - `adapters/input/input_controller.rb`
  - -> `adapters/input/reader_input_controller.rb`
- Moved command port adapter:
  - `adapters/runtime/session_state/command_port_adapter.rb`
  - -> `adapters/input/command_port_adapter.rb`

### Large-Class Decomposition

- Sidebar controller split into focused collaborators:
  - `application/controllers/sidebar/toc_navigation.rb`
  - `application/controllers/sidebar/anchor_resolver.rb`
  - `application/controllers/sidebar/tab_state_orchestrator.rb`
- Dictionary popup split into focused flows:
  - `presentation/ui/components/dictionary_popup/setup_flow.rb`
  - `presentation/ui/components/dictionary_popup/results_flow.rb`

### Dependency Bundle Cleanup

- Removed unused reader/runtime bundle fields (`file_probe`, `path_ops`) from:
  - `ReaderControllerDependencies`
  - `RuntimeBootstrapDependencies`
- Removed unused menu service bundle fields (`pagination_cache`, `display_capabilities`, `instrumentation`).

## Prior Cleanup Entries

- Removed `RuntimeConfigProvider` compatibility pattern in favor of explicit runtime-config injection.
- Removed internal zip shim (`lib/shoko/internal/**`, `lib/zip.rb`) in favor of adapter-owned archive access.
- Namespace normalizations for UI/application constants and port naming remain in effect.
