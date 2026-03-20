# frozen_string_literal: true

require_relative 'record_support'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dependencies
          # Grouped dependency records for DictionaryController.
          module DictionaryControllerDependencies
            StateDependencies = Data.define(
              :reader_state,
              :config_reader,
              :sidebar_state,
              :reader_session_mutator,
              :document,
              :rendered_content_reader
            ) do
              extend DependencyBuilder
              include Validation

              def self.required_fields
                %i[reader_state config_reader sidebar_state reader_session_mutator]
              end
            end

            ServiceDependencies = Data.define(
              :dictionary_service,
              :dictionary_catalog_service,
              :dictionary_availability,
              :dictionary_storage,
              :selection_service,
              :notification_service,
              :settings_service
            ) do
              extend DependencyBuilder
              include Validation

              def self.required_fields
                %i[notification_service]
              end
            end

            UiDependencies = Data.define(
              :layout_metrics,
              :terminal_service,
              :ui_component_factory,
              :dictionary_ui_session
            ) do
              extend DependencyBuilder
              include Validation

              def self.required_fields
                []
              end
            end

            ControllerDependencies = Data.define(
              :logger,
              :input_controller,
              :layout_service,
              :reader_controller,
              :ui_controller,
              :clock
            ) do
              extend DependencyBuilder
              include Validation

              def self.required_fields
                %i[clock]
              end
            end

            Bundle = Data.define(:state, :services, :ui, :controllers) do
              def self.build(**)
                new(
                  state: StateDependencies.build(**),
                  services: ServiceDependencies.build(**),
                  ui: UiDependencies.build(**),
                  controllers: ControllerDependencies.build(**)
                )
              end

              def validate!
                state.validate!
                services.validate!
                ui.validate!
                controllers.validate!
                self
              end
            end
          end
        end
      end
    end
  end
end
