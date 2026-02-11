# frozen_string_literal: true

module Shoko
  module Application
    module Composition
      module Dependencies
        # Groups Reader::RuntimeBootstrap collaborators into a single object.
        RuntimeBootstrapDependencies = Struct.new(
          :state,
          :doc,
          :terminal_service,
          :page_calculator,
          :clipboard_service,
          :layout_service,
          :rendering_factory,
          :input_system_factory,
          :config_reader,
          :reader_state_reader,
          :state_writer,
          :navigation_service,
          :bookmark_service,
          :selection_service,
          :rendered_content_reader,
          :annotation_service,
          :render_registry,
          :coordinate_service,
          :notification_service,
          :ui_component_factory,
          :layout_metrics,
          :dictionary_service,
          :dictionary_catalog_service,
          :settings_service,
          :dictionary_availability,
          :dictionary_storage,
          :runtime_config,
          :formatting_service,
          :dictionary_ui_session,
          :in_book_search_ui_session,
          :annotation_overlay_ui_session,
          :progress_repository,
          :bookmark_repository,
          :pagination_cache,
          :notification_writer,
          :async_executor,
          :display_capabilities,
          :instrumentation,
          :ui_state_reader,
          :sidebar_state_reader,
          :reader_ui_dependencies,
          :wrapping_service,
          :command_port,
          :logger,
          :file_probe,
          :path_ops,
          :clock,
          :process_control,
          keyword_init: true
        ) do
          RUNTIME_REQUIRED_FIELDS = %i[
            state
            doc
            terminal_service
            page_calculator
            clipboard_service
            layout_service
            rendering_factory
            input_system_factory
            config_reader
            reader_state_reader
            state_writer
            ui_state_reader
            sidebar_state_reader
            command_port
            dictionary_ui_session
            in_book_search_ui_session
            annotation_overlay_ui_session
          ].freeze

          def self.build(**kwargs)
            new(**kwargs)
          end

          def validate!
            missing = RUNTIME_REQUIRED_FIELDS.select { |field| public_send(field).nil? }
            return self if missing.empty?

            raise ArgumentError, "Missing required runtime bootstrap dependencies: #{missing.join(', ')}"
          end
        end
      end
    end
  end
end
