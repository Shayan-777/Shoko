# frozen_string_literal: true

require_relative 'dependency_validation'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dependencies
          # Core reader-controller collaborators: pagination, terminal, clipboard, timing.
          ReaderControllerCoreDependencies = Data.define(
            :page_calculator,
            :terminal_service,
            :clipboard_service,
            :instrumentation,
            :logger,
            :clock,
            :process_control
          ) do
            include DependencyValidation

            def self.required_fields
              %i[page_calculator terminal_service clipboard_service clock]
            end
          end
        end
      end
    end
  end
end
