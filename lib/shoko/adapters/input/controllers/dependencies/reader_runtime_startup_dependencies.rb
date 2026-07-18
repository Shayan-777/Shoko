# frozen_string_literal: true

require_relative 'dependency_validation'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dependencies
          # Startup-path collaborators: intent handling, document loading, editors.
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
            include DependencyValidation

            def self.required_fields
              %i[
                intent_handler_factory
                pending_jump_handler_factory
                document_loader
                annotation_editor_launcher
              ]
            end
          end
        end
      end
    end
  end
end
