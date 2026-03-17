# Runtime Handoff

This document describes the current startup flow and the menu-to-reader handoff after the session-store cleanup.

## Startup Sequence

1. `bin/shoko` builds `Shoko::Application::UnifiedApplication`.
2. `Shoko::Composition::ContainerFactory.create_default_container` registers core ports, application services, runtime state, and controller builders.
3. Runtime state is initialized through `ObserverStateStore`, with canonical defaults coming from `Shoko::Core::Models::Session::Schema`.
4. Adapter-facing reads happen through direct stores:
   - `app_config_store`
   - `reader_session_store`
   - `menu_session_store`
5. Live terminal and reader-runtime values are exposed through `reader_runtime_context`.
6. Menu startup builds `MenuController` with direct stores plus `reader_runtime_context` for terminal/loading reads.
7. Reader startup builds `MouseableReader` through `controller_composition/reader_builder/assembly.rb`, which:
   - resolves container dependencies
   - prepares runtime services and background worker state
   - builds `ReaderUiDependencies`
   - builds controller dependency records
   - groups runtime wiring into `ReaderPlatformContext`, `ReaderStateContext`, `ReaderUiContext`, and `ReaderServiceContext`
   - hands that grouped context to `ReaderRuntimeAssembler`

## Menu To Reader Handoff

1. The menu selects a target path and hands it to `MenuStateControllerComposer`.
2. `ReaderLaunchService` resolves the canonical path, prepares a preloaded document when possible, and stores launch-scoped objects in `reader_launch_state`.
3. The reader builder reuses:
   - `reader_launch_state.preloaded_document`
   - `reader_launch_state.background_worker`
4. The builder writes durable reader state through `reader_session_store` and `reader_session_mutator`.
5. The builder keeps live UI objects out of persisted state:
   - popup overlays and panels live in `reader_ui_session_registry`
   - terminal size and capability reads come from `reader_runtime_context`
6. During reader runtime:
   - persisted session/config reads come from direct stores
   - render/layout/input services consume grouped runtime contexts instead of a single wide dependency record
7. On return to menu, reader progress/bookmarks/annotations are already stored through the same direct ports, so the menu can resume without wrapper projections.

## State Ownership

- `Session::Schema` is the single source of truth for session/config field lists and defaults.
- `ReaderSnapshot`, `MenuSnapshot`, and `ConfigSnapshot` derive their fields/defaults from that schema.
- `ReaderSessionStoreAdapter`, `MenuSessionStoreAdapter`, and `AppConfigStoreAdapter` own snapshot load/save/update behavior.
- `ReaderUiSessionRegistry` owns only live UI objects.
- `ReaderRuntimeContextAdapter` owns terminal size, loading projection, and display capability calculation.
