# frozen_string_literal: true

require_relative 'dependency_record_mixins'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dependencies
          # Grouped dependency records for UIController.
          module UiControllerDependencies
            StateDependencies = Data.define(
              :reader_state,
              :config_reader,
              :reader_session_mutator,
              :sidebar_state,
              :ui_state,
              :selection_service,
              :rendered_content_reader
            ) do
              extend DependencyBuilder
              include Validation

              def self.required_fields
                %i[reader_state config_reader reader_session_mutator]
              end
            end

            ControllerDependencies = Data.define(
              :sidebar_controller,
              :dictionary_controller,
              :annotation_controller,
              :in_book_search_controller,
              :toc_controller,
              :input_controller,
              :reader_controller
            ) do
              extend DependencyBuilder
              include Validation

              def self.required_fields
                %i[
                  sidebar_controller
                  dictionary_controller
                  annotation_controller
                  in_book_search_controller
                  toc_controller
                  input_controller
                ]
              end
            end

            ServiceDependencies = Data.define(
              :notification_service,
              :clipboard_service,
              :ui_component_factory,
              :annotation_service,
              :translation_service,
              :logger
            ) do
              extend DependencyBuilder
              include Validation

              def self.required_fields
                %i[notification_service]
              end
            end

            Bundle = Data.define(:state, :controllers, :services) do
              def self.build(**)
                new(
                  state: StateDependencies.build(**),
                  controllers: ControllerDependencies.build(**),
                  services: ServiceDependencies.build(**)
                )
              end

              def validate!
                state.validate!
                controllers.validate!
                services.validate!
                self
              end
            end
          end
        end
      end
    end
  end
end
