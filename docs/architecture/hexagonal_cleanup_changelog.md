# Hexagonal Cleanup Changelog

## V6 Hard-Cut Boundary Cleanup

### Boundary enforcement

- Added strict layer dependency spec at `spec/core/architecture/layer_dependency_spec.rb`.
- Enforced matrix rules:
  - `core -> core/shared`
  - `application -> application/core/shared`
  - `adapters -> adapters/application/core/shared`
  - `bootstrap -> bootstrap/adapters/application/core/shared`
  - `shared -> shared`
- Added explicit forbidden checks for:
  - `application`/`adapters` requiring `bootstrap/*`,
  - `shared` requiring `adapters/*`,
  - `Shoko::Bootstrap::*` usage outside bootstrap/bin/test_support,
  - `context.ui_controller` / `context.state_controller` usage in application commands.

### Layer leak removals

- Removed `shared -> adapters` aliases for runtime config, ANSI, and Kitty placeholders.
- Moved Kitty placeholder implementation/data to `shared/terminal`.
- Removed `shared/terminal/device.rb` shim.

### Composition and ownership cleanup

- Moved controller dependency bundles from `bootstrap/dependencies/*` to:
  - `adapters/input/controllers/dependencies/*`
- Updated namespaces from `Shoko::Bootstrap::Dependencies::*` to
  `Shoko::Adapters::Input::Controllers::Dependencies::*`.

### Application/bootstrap decoupling

- Refactored `Application::UnifiedApplication` to injected dependencies:
  - new initializer: `initialize(epub_path = nil, deps:)`
- Added bootstrap-side factory:
  - `Shoko::Bootstrap::ContainerFactory.build_unified_application(epub_path:, log_config:)`
- Refactored `CLI.run` to injected boot hooks:
  - `run(argv = ARGV, preflight_checker:, app_factory:, migration_error_class:)`
- Updated `bin/start` to provide bootstrap wiring explicitly.

### Command boundary hard cut

- Reduced `Application::UseCases::CommandBus` to semantic commands only:
  - navigation + bookmark.
- Moved reader/menu UI control bindings to adapter-local lambdas.
- Removed adapter-coupled application command artifacts:
  - `application_commands.rb`
  - `menu_commands.rb`
  - `conditional_navigation_commands.rb`
  - `sidebar_commands.rb`
  - `annotation_editor_commands.rb`
  - `reader_commands.rb`
  - `reader_intent_commands.rb`
- Fixed bookmark command execution gating:
  - `BookmarkCommand#can_execute?` now checks `bookmark_service` contract.

### Core pagination ports

- Added outbound ports:
  - `Core::Ports::Outbound::LineWrapper`
  - `Core::Ports::Outbound::ChapterFormatter`
- Updated pagination collaborators to use explicit port dependencies.
- Updated formatting adapters to include new port contracts.

## V5 Final Hard-Cut Migration

### Structural hard cut

- Consolidated the architecture to one canonical shape:
  - `core/ports/{inbound,outbound}`
  - `application/{use_cases,services,workflows}`
  - `adapters/{input,ui,output,runtime,storage,monitoring}`
  - `bootstrap/{container_factory,dependencies}`
  - `shared/`

### Port unification and boundary cleanup

- Completed single ports-root migration under `core/ports`.
- Added inbound command boundary:
  - `Core::Ports::Inbound::CommandBus`
  - `Application::UseCases::CommandBus` as implementation.
- Removed removed/obsolete command-port contract and adapter artifacts.
- Removed adapter-local interface contracts from `core/ports/outbound` and kept them adapter-internal.

### Input/UI relocation and semantic cleanup

- Completed hard relocation of controller ownership to `adapters/input/controllers`.
- Completed hard relocation of UI ownership to `adapters/ui` (components, rendering, sessions, view models).
- Moved dependency bundles into bootstrap-owned dependency namespace and location.

### UI terminal primitive cleanup

- Added shared terminal primitives under `shared/terminal`.
- Repointed UI code to shared terminal primitives.
- Eliminated direct UI imports from sibling adapter domains.

### Architecture enforcement rewrite

- Rewrote architecture specs to enforce:
  - single ports root split by direction,
  - no legacy directories/constants,
  - no UI adapter coupling to sibling adapter domains,
  - bootstrap-only container mutation/resolution.

## Prior Migration Phases

- Earlier phases introduced the large runtime/state/output cleanup.
- V5 supersedes earlier target-shape guidance and is now the only canonical model.
