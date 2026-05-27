# frozen_string_literal: true

require_relative '../../../adapters/runtime/session_state/session_schema_reset_guard'
require_relative '../../../application/state/observer_state_store'
require_relative '../../../application/state/schema_registry'
require_relative '../../../core/reading/schema'
require_relative '../../../application/state/schema/reader_process'
require_relative '../../../application/state/schema/reader_pagination'
require_relative '../../../application/state/schema/reader_view'
require_relative '../../../application/state/schema/menu_process'
require_relative '../../../application/state/schema/menu_transient'
require_relative '../../../application/state/schema/config'
require_relative '../../../application/state/schema/ui_globals'
require_relative '../../../adapters/runtime/session_state/app_config_store_adapter'
require_relative '../../../adapters/ui/state/reader_component_registry'
require_relative '../../../adapters/runtime/session_state/reader_session_store_adapter'
require_relative '../../../adapters/runtime/session_state/reader_view_state_store_adapter'
require_relative '../../../adapters/runtime/session_state/reader_pagination_store_adapter'
require_relative '../../../adapters/runtime/session_state/reader_snapshot_projection_adapter'
require_relative '../../../adapters/runtime/session_state/reader_runtime_context_adapter'
require_relative '../../../adapters/runtime/session_state/reader_session_mutator'
require_relative '../../../adapters/runtime/session_state/menu_session_store_adapter'
require_relative '../../../adapters/runtime/session_state/menu_transient_store_adapter'
require_relative '../../../adapters/runtime/session_state/menu_snapshot_projection_adapter'
require_relative '../../../adapters/runtime/session_state/menu_session_mutator'

module Shoko
  module Composition
    module ContainerFactory
      # Registers state-store + state-bridging adapters in the DI container.
      #
      # Composition is the only layer permitted to assemble cross-layer state:
      # it knows both the application state store and the UI's component
      # registry, and it builds the schema registry from per-layer schema
      # fragments before constructing the store.
      module PortAndRepositoryRegistrationStateManagement
        def register_state_management(container, event_bus)
          register_schema_registry(container)
          register_global_state(container, event_bus)
          container.register_factory(:state_store) { |c| c.resolve(:global_state) }
          register_hexagonal_adapters(container)
        end

        def register_hexagonal_adapters(container)
          register_reader_state_adapters(container)
          register_menu_state_adapters(container)
          register_reader_ui_adapters(container)
          register_render_state_adapters(container)
        end

        private

        def register_schema_registry(container)
          container.register_singleton(:schema_registry) do |_c|
            Shoko::Application::State::SchemaRegistry.new
              .register(Shoko::Core::Reading::Schema)
              .register(Shoko::Application::State::Schema::ReaderProcess)
              .register(Shoko::Application::State::Schema::ReaderPagination)
              .register(Shoko::Application::State::Schema::ReaderView)
              .register(Shoko::Application::State::Schema::MenuProcess)
              .register(Shoko::Application::State::Schema::MenuTransient)
              .register(Shoko::Application::State::Schema::Config)
              .register(Shoko::Application::State::Schema::UiGlobals)
          end
        end

        def register_global_state(container, event_bus)
          container.register_singleton(:global_state) do |c|
            Shoko::Adapters::Runtime::SessionState::SessionSchemaResetGuard.new(
              config_storage: c.resolve(:config_storage),
              cache_paths: c.resolve(:cache_paths),
              logger: c.resolve(:logger)
            ).ensure_current_schema!
            Shoko::Application::State::ObserverStateStore.new(
              event_bus,
              config_storage: c.resolve(:config_storage),
              terminal_capabilities: c.resolve(:terminal_capabilities),
              schema_registry: c.resolve(:schema_registry),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_reader_state_adapters(container)
          register_reader_store_adapters(container)
          register_reader_runtime_adapters(container)
        end

        def register_reader_store_adapters(container)
          container.register_factory(:app_config_store) do |c|
            Shoko::Adapters::Runtime::SessionState::AppConfigStoreAdapter.new(c.resolve(:global_state))
          end
          container.register_singleton(:reader_component_registry) do |_c|
            Shoko::Adapters::Ui::State::ReaderComponentRegistry.new
          end
          container.register_factory(:reader_session_store) do |c|
            Shoko::Adapters::Runtime::SessionState::ReaderSessionStoreAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:reader_view_state_store) do |c|
            Shoko::Adapters::Runtime::SessionState::ReaderViewStateStoreAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:reader_pagination_store) do |c|
            Shoko::Adapters::Runtime::SessionState::ReaderPaginationStoreAdapter.new(c.resolve(:global_state))
          end
        end

        def register_reader_runtime_adapters(container)
          register_reader_state_projection(container)
          register_reader_runtime_context_adapter(container)
          register_reader_session_mutator_adapter(container)
        end

        def register_reader_state_projection(container)
          container.register_factory(:reader_state_reader) do |c|
            Shoko::Adapters::Runtime::SessionState::ReaderSnapshotProjectionAdapter.new(
              state: c.resolve(:global_state),
              reader_session_store: c.resolve(:reader_session_store),
              reader_view_state_store: c.resolve(:reader_view_state_store),
              reader_pagination_store: c.resolve(:reader_pagination_store),
              component_registry: c.resolve(:reader_component_registry)
            )
          end
        end

        def register_reader_runtime_context_adapter(container)
          container.register_factory(:reader_runtime_context) do |c|
            Shoko::Adapters::Runtime::SessionState::ReaderRuntimeContextAdapter.new(
              terminal_session: c.resolve(:terminal_session),
              display_capabilities: c.resolve(:display_capabilities),
              app_config_store: c.resolve(:app_config_store),
              reader_view_state_store: c.resolve(:reader_view_state_store),
              reader_pagination_store: c.resolve(:reader_pagination_store)
            )
          end
        end

        def register_reader_session_mutator_adapter(container)
          container.register_factory(:reader_session_mutator) do |c|
            Shoko::Adapters::Runtime::SessionState::ReaderSessionMutator.new(
              reader_session_store: c.resolve(:reader_session_store),
              reader_view_state_store: c.resolve(:reader_view_state_store),
              reader_pagination_store: c.resolve(:reader_pagination_store),
              app_config_store: c.resolve(:app_config_store),
              component_registry: c.resolve(:reader_component_registry)
            )
          end
        end

        def register_menu_state_adapters(container)
          register_menu_store_adapters(container)
          register_menu_mutation_adapters(container)
        end

        def register_menu_store_adapters(container)
          container.register_factory(:menu_session_store) do |c|
            Shoko::Adapters::Runtime::SessionState::MenuSessionStoreAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:menu_transient_store) do |c|
            Shoko::Adapters::Runtime::SessionState::MenuTransientStoreAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:menu_snapshot_projection) do |c|
            Shoko::Adapters::Runtime::SessionState::MenuSnapshotProjectionAdapter.new(
              state: c.resolve(:global_state),
              menu_session_store: c.resolve(:menu_session_store),
              menu_transient_store: c.resolve(:menu_transient_store)
            )
          end
        end

        def register_menu_mutation_adapters(container)
          container.register_factory(:menu_session_mutator) do |c|
            Shoko::Adapters::Runtime::SessionState::MenuSessionMutator.new(
              menu_session_store: c.resolve(:menu_session_store),
              menu_transient_store: c.resolve(:menu_transient_store)
            )
          end
        end
      end
    end
  end
end
