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
  - `Shoko::Application::Ports::CommandPort`

## Finalized Runtime Policies

- Composition root is `application/composition` (container mechanics + wiring).
- `lib/shoko.rb` is bootstrap-only.
- Runtime config is injected through `Core::Ports::RuntimeConfig` implementations.
- No global runtime-config provider exists.
- Archive access is adapter-owned via `Shoko::Adapters::BookSources::Archive::ZipReader`.
- Core pagination services accept explicit layout inputs (`width`, `height`, `sidebar_visible`) and do not depend on UI readers in constructors.
- Legacy runtime shims and compatibility aliases are removed from production paths.

## Guardrails

- Core UI-coupled shim ports must not exist.
- Deprecated DI keys must not be registered or resolved.
- `register_deprecated*` and deprecation warning plumbing are forbidden.
- `configure_runtime_config` compatibility hooks are forbidden.
- `lib/shoko/internal/**` and `lib/zip.rb` are forbidden.
