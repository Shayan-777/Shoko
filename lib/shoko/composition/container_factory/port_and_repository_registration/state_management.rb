# frozen_string_literal: true

require_relative '../../../adapters/runtime/session_state/session_schema_reset_guard'
require_relative '../../../adapters/runtime/session_state/observer_state_store'
require_relative '../../../adapters/runtime/session_state/app_config_store_adapter'
require_relative '../../../adapters/runtime/session_state/reader_ui_session_registry'
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
      # Registers runtime session-state adapters used by composition roots.
      module PortAndRepositoryRegistrationStateManagement
        def register_state_management(container, event_bus)
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

        def register_global_state(container, event_bus)
          container.register_singleton(:global_state) do |c|
            Shoko::Adapters::Runtime::SessionState::SessionSchemaResetGuard.new(
              config_storage: c.resolve(:config_storage),
              cache_paths: c.resolve(:cache_paths),
              logger: c.resolve(:logger)
            ).ensure_current_schema!
            Shoko::Adapters::Runtime::SessionState::ObserverStateStore.new(
              event_bus,
              config_storage: c.resolve(:config_storage),
              terminal_capabilities: c.resolve(:terminal_capabilities),
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
          container.register_singleton(:reader_ui_session_registry) do |_c|
            Shoko::Adapters::Runtime::SessionState::ReaderUiSessionRegistry.new
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
              ui_session_registry: c.resolve(:reader_ui_session_registry)
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
              ui_session_registry: c.resolve(:reader_ui_session_registry)
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
