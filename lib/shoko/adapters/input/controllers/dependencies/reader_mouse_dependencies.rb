# frozen_string_literal: true

require_relative 'dependency_validation'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dependencies
          # UI/composition collaborators for the reader's mouse state machine.
          ReaderMouseDependencies = Data.define(
            :formatting_service,
            :layout_service,
            :dictionary_availability,
            :ui_component_factory,
            :ui_state_reader
          ) do
            include DependencyValidation

            def self.required_fields
              %i[formatting_service layout_service dictionary_availability ui_component_factory]
            end
          end
        end
      end
    end
  end
end
