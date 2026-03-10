# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dependencies
          module RecordBuilder
            def build(**kwargs)
              new(**members.to_h { |key| [key, kwargs[key]] })
            end
          end

          module Validation
            def validate!
              missing = Array(self.class.required_fields).select { |field| public_send(field).nil? }
              return self if missing.empty?

              raise ArgumentError, "Missing required #{self.class.name.split('::').last}: #{missing.join(', ')}"
            end
          end

          ReaderControllerCoreDependencies = Data.define(
            :page_calculator,
            :terminal_service,
            :clipboard_service,
            :instrumentation,
            :logger,
            :clock,
            :process_control
          ) do
            extend RecordBuilder
            include Validation

            def self.required_fields
              %i[page_calculator terminal_service clipboard_service clock]
            end
          end

          ReaderControllerStateDependencies = Data.define(
            :observer_registry,
            :config_reader,
            :reader_state_reader,
            :reader_session_mutator,
            :ui_state_reader,
            :selection_service,
            :wrapping_service
          ) do
            extend RecordBuilder
            include Validation

            def self.required_fields
              %i[config_reader reader_state_reader reader_session_mutator ui_state_reader]
            end
          end

          ReaderControllerServiceDependencies = Data.define(
            :navigation_service,
            :bookmark_service,
            :popup_position_service,
            :rendered_content_reader,
            :annotation_service,
            :render_registry,
            :coordinate_service
          ) do
            extend RecordBuilder
            include Validation

            def self.required_fields
              %i[rendered_content_reader coordinate_service]
            end
          end

          ReaderRuntimeBootDependencies = Data.define(
            :reader_lifecycle_factory,
            :terminal_session,
            :background_worker,
            :background_worker_builder,
            :async_executor,
            :instrumentation_service,
            :pagination_cache_preloader
          ) do
            extend RecordBuilder
            include Validation

            def self.required_fields
              %i[reader_lifecycle_factory terminal_session background_worker_builder]
            end
          end

          ReaderRuntimeStartupDependencies = Data.define(
            :intent_handler_factory,
            :pending_jump_handler_factory,
            :document_loader,
            :reader_document_locator,
            :reader_launch_state,
            :document,
            :annotation_editor_launcher,
            :key_classifier
          ) do
            extend RecordBuilder
            include Validation

            def self.required_fields
              %i[
                intent_handler_factory
                pending_jump_handler_factory
                document_loader
                annotation_editor_launcher
              ]
            end
          end

          MouseableReaderDependencies = Data.define(
            :formatting_service,
            :layout_service,
            :dictionary_availability,
            :ui_component_factory,
            :ui_state_reader
          ) do
            extend RecordBuilder
            include Validation

            def self.required_fields
              %i[formatting_service layout_service dictionary_availability ui_component_factory]
            end
          end
        end
      end
    end
  end
end
