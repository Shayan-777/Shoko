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
3. Adapters must avoid global mutable configuration for runtime behavior.
4. Transitional shims may exist only when explicitly documented and tested.

## Migration Notes

Pagination orchestration moved to `Shoko::Application::Services::Pagination`.
Legacy `Shoko::Core::Services::Pagination::*` constants are temporary wrappers.
Core UI/menu port files under `core/ports` are deprecated compatibility shims and are no longer consumed by adapters.
`Shoko::Adapters::BookSources::BookFinder` class-level shim methods remain transitional and are explicit opt-in only (`install_default`/`configure`).
Next cleanup phase removes deprecated core UI/menu shim contracts after compatibility window ends.
