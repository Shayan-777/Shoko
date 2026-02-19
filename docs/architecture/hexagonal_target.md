# Hexagonal Target Boundaries

## Intent

Shoko follows a strict Hexagonal Architecture where dependency flow points inward.

- `core` contains domain models, domain services, and domain-centric ports only.
- `application` orchestrates workflows and owns UI/menu/presentation contracts.
- `adapters` implement IO, runtime, storage, and UI details.
- `application/composition` is the composition root and the only place that wires concrete implementations.

## Boundary Rules

1. Core must not define or depend on UI/menu/popup/loading contracts.
2. Controllers/workflows must not instantiate core services directly; services are injected from composition.
3. Application owns reader/menu orchestration services and UI-facing contracts.
4. Adapters must avoid mutable global runtime configuration hooks.
5. No transitional compatibility shims are kept in runtime code.

## Finalized Ownership

- Reader/UI orchestration services:
  - `Shoko::Application::Services::Reader::NavigationService`
  - `Shoko::Application::Services::Reader::BookmarkService`
  - `Shoko::Application::Services::Pagination::PaginationCachePreloader`
- UI/pagination/input contracts:
  - `Shoko::Application::Ports::UiStateReader`
  - `Shoko::Application::Ports::SidebarStateReader`
  - `Shoko::Application::Ports::InputSystemFactory`
  - `Shoko::Application::Ports::PaginationStateWriter`
  - `Shoko::Application::Ports::ReaderStateWriter`

## Guardrails

- Core UI-coupled shim ports must not exist.
- Deprecated DI keys must not be registered or resolved.
- `register_deprecated*` and deprecation warning plumbing are forbidden.
- `configure_runtime_config` compatibility hooks are forbidden.
