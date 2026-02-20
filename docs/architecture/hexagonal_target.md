# Hexagonal Target Boundaries

## Intent

Shoko follows strict Hexagonal Architecture with inward dependencies:

- `core` owns domain models/services and domain/infrastructure-facing ports.
- `application` owns orchestration workflows, use-cases, controllers, and application-facing ports.
- `adapters` own runtime/storage/input/output integrations and port implementations.
- `presentation/ui` owns UI components, rendering pipeline, UI sessions, and rendering models.
- `bootstrap` is the only composition root.

## Target Layout (V4)

```text
lib/shoko/
  bootstrap/
  presentation/ui/
  adapters/
    runtime/session_state/
    output/{terminal,formatting,kitty,layout,...}
  application/
    dependencies/
    controllers/
    services/
    ports/
  core/
```

## Layer Ownership

### Core-owned ports (domain/infrastructure)

- `Core::Ports::FileProbe`
- `Core::Ports::PathOps`
- `Core::Ports::ProcessControl`
- `Core::Ports::Clock`
- `Core::Ports::EventPublisher`
- `Core::Ports::RuntimeConfig`
- `Core::Ports::TextMetrics`
- `Core::Ports::DisplayCapabilities`
- `Core::Ports::Instrumentation`
- `Core::Ports::AsyncExecutor`
- domain persistence ports (`BookmarkRepository`, `AnnotationRepository`, etc.)

### Application-owned orchestration/UI/input ports

- `Application::Ports::ConfigReader`
- `Application::Ports::ReaderNavigationReader`
- `Application::Ports::KeyClassifier`
- `Application::Ports::NotificationWriter`
- `Application::Ports::UiStateReader`
- `Application::Ports::SidebarStateReader`
- `Application::Ports::ReaderOverlayStateReader`
- `Application::Ports::PaginationStateWriter`
- `Application::Ports::ReaderStateWriter`
- `Application::Ports::CommandPort`
- `Application::Ports::InputSystemFactory`
- `Application::Ports::UiComponentFactory`
- `Application::Ports::RenderingFactory`
- `Application::Ports::RenderStateWriter`
- `Application::Ports::DictionaryUiSession`
- `Application::Ports::InBookSearchUiSession`
- `Application::Ports::AnnotationOverlayUiSession`

## Structural Decisions (V4)

- Composition root lives at top-level `bootstrap`.
- Runtime session state lives under `adapters/runtime/session_state`.
- UI and rendering ownership lives under `presentation/ui`.
- Rendering models live under `presentation/ui/rendering/models`.
- Render registry lives at `presentation/ui/render_registry.rb`.
- Reader rendering ownership consolidated under:
  - `presentation/ui/rendering/views/**`
  - `presentation/ui/rendering/line/**`

## Purity Rules

- Core services do not mutate application state directly.
- Application services/orchestrators apply state writes.
- Runtime config is constructor/thread-context injected.
- No compatibility shims/aliases for removed legacy paths or constants.

## Forbidden Legacy Artifacts

- No pre-V4 composition/state/output-ui legacy trees.
- No pre-V4 legacy namespaces from the previous layout.
