# Hexagonal Cleanup Changelog

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
