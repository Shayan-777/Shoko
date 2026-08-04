# frozen_string_literal: true

require_relative 'dependency_builder'
require_relative 'dependency_validation'
require 'shoko/application/ports/outbound/progress_repository'

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
              :reader_session_mutator,
              :rendered_content_reader
            ) do
              extend DependencyBuilder
              include DependencyValidation

              def self.required_fields
                %i[reader_state config_reader ui_state reader_session_mutator]
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
              include DependencyValidation

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
              :anchor_resolver
            ) do
              extend DependencyBuilder
              include DependencyValidation

              def self.required_fields
                %i[progress_repository notification_service]
              end

              def validate!
                super

                return self if progress_repository.is_a?(Shoko::Application::Ports::Outbound::ProgressRepository)

                raise ArgumentError, 'progress_repository must implement Application::Ports::Outbound::ProgressRepository'
              end
            end

            Bundle = Data.define(:session, :document, :services) do
              def self.groups = [SessionDependencies, DocumentDependencies, ServiceDependencies]

              def self.build(**dependencies)
                allowed = groups.flat_map(&:members).uniq
                SessionDependencies.reject_unknown_dependencies!(dependencies.keys, allowed: allowed, label: 'Bundle')
                new(
                  session: SessionDependencies.build_from(dependencies),
                  document: DocumentDependencies.build_from(dependencies),
                  services: ServiceDependencies.build_from(dependencies)
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
