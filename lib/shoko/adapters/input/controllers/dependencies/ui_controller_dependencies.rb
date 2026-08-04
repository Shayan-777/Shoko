# frozen_string_literal: true

require_relative 'dependency_builder'
require_relative 'dependency_validation'

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
              :ui_state,
              :selection_service,
              :rendered_content_reader
            ) do
              extend DependencyBuilder
              include DependencyValidation

              def self.required_fields
                %i[reader_state config_reader reader_session_mutator]
              end
            end

            ControllerDependencies = Data.define(
              :dictionary_controller,
              :annotation_controller,
              :in_book_search_controller,
              :toc_controller,
              :translator_controller,
              :notes_controller,
              :input_controller,
              :reader_controller
            ) do
              extend DependencyBuilder
              include DependencyValidation

              def self.required_fields
                %i[
                  dictionary_controller
                  annotation_controller
                  in_book_search_controller
                  toc_controller
                  translator_controller
                  notes_controller
                  input_controller
                ]
              end
            end

            ServiceDependencies = Data.define(
              :notification_service,
              :clipboard_service,
              :ui_component_factory,
              :annotation_service,
              :logger
            ) do
              extend DependencyBuilder
              include DependencyValidation

              def self.required_fields
                %i[notification_service]
              end
            end

            Bundle = Data.define(:state, :controllers, :services) do
              def self.groups = [StateDependencies, ControllerDependencies, ServiceDependencies]

              def self.build(**dependencies)
                allowed = groups.flat_map(&:members).uniq
                StateDependencies.reject_unknown_dependencies!(dependencies.keys, allowed: allowed, label: 'Bundle')
                new(
                  state: StateDependencies.build_from(dependencies),
                  controllers: ControllerDependencies.build_from(dependencies),
                  services: ServiceDependencies.build_from(dependencies)
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
