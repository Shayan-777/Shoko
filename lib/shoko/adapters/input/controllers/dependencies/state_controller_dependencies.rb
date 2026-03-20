# frozen_string_literal: true

require_relative 'record_support'
require_relative '../../../../core/ports/outbound/progress_repository'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dependencies
          # Grouped dependency records for StateController.
          module StateControllerDependencies
            SessionDependencies = Data.define(
              :reader_state,
              :config_reader,
              :ui_state,
              :sidebar_state,
              :reader_session_mutator,
              :rendered_content_reader
            ) do
              extend DependencyBuilder
              include Validation

              def self.required_fields
                %i[reader_state config_reader ui_state sidebar_state reader_session_mutator]
              end
            end

            DocumentDependencies = Data.define(
              :doc,
              :document_reader,
              :path,
              :terminal_service,
              :page_calculator,
              :layout_service,
              :process_control
            ) do
              extend DependencyBuilder
              include Validation

              def self.required_fields
                []
              end
            end

            ServiceDependencies = Data.define(
              :progress_repository,
              :bookmark_repository,
              :annotation_service,
              :logger,
              :navigation_service,
              :bookmark_service,
              :notification_service,
              :coordinate_service
            ) do
              extend DependencyBuilder
              include Validation

              def self.required_fields
                %i[progress_repository notification_service]
              end

              def validate!
                super

                return self if progress_repository.is_a?(Shoko::Core::Ports::Outbound::ProgressRepository)

                raise ArgumentError, 'progress_repository must implement Core::Ports::Outbound::ProgressRepository'
              end
            end

            Bundle = Data.define(:session, :document, :services) do
              def self.build(**)
                new(
                  session: SessionDependencies.build(**),
                  document: DocumentDependencies.build(**),
                  services: ServiceDependencies.build(**)
                )
              end

              def validate!
                session.validate!
                document.validate!
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
