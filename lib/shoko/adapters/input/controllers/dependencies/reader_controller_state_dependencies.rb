# frozen_string_literal: true

require_relative 'dependency_validation'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dependencies
          # State readers/mutators the reader controller observes and drives.
          ReaderControllerStateDependencies = Data.define(
            :observer_registry,
            :config_reader,
            :reader_state_reader,
            :reader_session_mutator,
            :ui_state_reader,
            :selection_service,
            :wrapping_service
          ) do
            include DependencyValidation

            def self.required_fields
              %i[config_reader reader_state_reader reader_session_mutator ui_state_reader]
            end
          end
        end
      end
    end
  end
end
