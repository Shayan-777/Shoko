# frozen_string_literal: true

require_relative 'record_support'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dependencies
          # Grouped dependency records for SidebarController.
          module SidebarControllerDependencies
            StateDependencies = Data.define(
              :reader_state,
              :config_reader,
              :ui_state,
              :sidebar_state,
              :reader_session_mutator,
              :document,
              :document_reader
            ) do
              extend DependencyBuilder
              include Validation

              def self.required_fields
                %i[reader_state config_reader ui_state sidebar_state reader_session_mutator]
              end
            end

            ServiceDependencies = Data.define(
              :navigation_service,
              :bookmark_service,
              :state_controller,
              :ui_controller,
              :notification_service
            ) do
              extend DependencyBuilder
              include Validation

              def self.required_fields
                %i[notification_service]
              end
            end

            UiDependencies = Data.define(:formatting_service, :layout_service) do
              extend DependencyBuilder
              include Validation

              def self.required_fields
                []
              end
            end

            Bundle = Data.define(:state, :services, :ui) do
              def self.build(**)
                new(
                  state: StateDependencies.build(**),
                  services: ServiceDependencies.build(**),
                  ui: UiDependencies.build(**)
                )
              end

              def validate!
                state.validate!
                services.validate!
                ui.validate!
                self
              end
            end
          end
        end
      end
    end
  end
end
