# Hexagonal Target Boundaries

## Intent

Shoko follows strict Hexagonal Architecture with inward dependencies:

- `core` owns domain logic and all ports.
- `application` owns use-case/workflow/service orchestration only.
- `adapters` own all driving/driven integrations.
- `bootstrap` is the only composition root.
- `shared` contains cross-adapter primitives with no feature orchestration.

## Canonical Layout (V5)

```text
lib/shoko/
  core/
    ports/
      inbound/
      outbound/
  application/
    use_cases/
    services/
    workflows/
  adapters/
    input/
      controllers/
      annotations/
      validators/
    ui/
      components/
      rendering/
      sessions/
      view_models/
      constants/
    output/
      terminal/
      formatting/
      kitty/
      clipboard/
    runtime/
    storage/
    monitoring/
  bootstrap/
    container_factory/
    dependencies/
  shared/
```

## Ports Rules

- One physical ports root only: `core/ports`.
- Inbound contracts live only in `core/ports/inbound`.
- Outbound contracts live only in `core/ports/outbound`.
- Adapter-local contracts must not live under `core/ports`.

## Key Inbound Contract

- `Core::Ports::Inbound::CommandBus`
- Implemented by `Application::UseCases::CommandBus`

## Enforcement Rules

- No legacy architecture directories under `application` for controllers/ui/ports/dependencies.
- No legacy UI tree outside `adapters/ui`.
- No direct dependency from `adapters/ui` into sibling adapter domains (`output/input/storage/runtime`).
- Container resolution and mutation are restricted to `bootstrap` composition roots (plus CLI boot entrypoints).
- No compatibility aliases or shims for removed architecture paths/constants.
