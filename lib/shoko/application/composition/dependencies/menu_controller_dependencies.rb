# frozen_string_literal: true

module Shoko
  module Application
    module Composition
      module Dependencies
        # Groups MenuController collaborators to reduce constructor bloat.
        MenuControllerDependencies = Struct.new(
          :state,
          :catalog,
          :terminal_service,
          :frame_coordinator,
          :render_pipeline,
          :menu_ui_dependencies,
          :build_reader_controller,
          :ui_component_factory,
          :key_classifier,
          :input_system_factory,
          :notification_service,
          :settings_service,
          :annotation_service,
          :logger,
          :pagination_cache,
          :display_capabilities,
          :instrumentation,
          :download_service,
          :dictionary_catalog_service,
          :text_sanitizer,
          :background_worker_factory,
          :recent_files_repository,
          :cache_pointer_resolver,
          :dictionary_availability,
          :dictionary_storage,
          :page_calculator,
          :layout_service,
          :wrapping_service,
          :document_service_factory,
          :config_reader,
          :reader_state_reader,
          :state_writer,
          :pagination_cache_preloader,
          :runtime_config,
          :reader_session_context,
          :menu_session_context,
          :document,
          :menu_state_reader,
          :menu_state_writer,
          :command_port,
          :file_probe,
          :path_ops,
          :clock,
          :process_control,
          keyword_init: true
        ) do
          MENU_REQUIRED_FIELDS = %i[
            state
            catalog
            terminal_service
            frame_coordinator
            render_pipeline
            menu_ui_dependencies
            build_reader_controller
            ui_component_factory
            key_classifier
            input_system_factory
            menu_state_reader
            menu_state_writer
            command_port
          ].freeze

          def self.build(**kwargs)
            new(**kwargs)
          end

          def validate!
            missing = MENU_REQUIRED_FIELDS.select { |field| public_send(field).nil? }
            return self if missing.empty?

            raise ArgumentError, "Missing required menu dependencies: #{missing.join(', ')}"
          end
        end
      end
    end
  end
end
