# frozen_string_literal: true

require_relative 'dependency_validation'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dependencies
          # Process/runtime collaborators needed to boot the reader lifecycle.
          ReaderRuntimeBootDependencies = Data.define(
            :reader_lifecycle_factory,
            :terminal_session,
            :background_worker,
            :background_worker_builder,
            :async_executor,
            :instrumentation_service,
            :warmup_services
          ) do
            include DependencyValidation

            def self.required_fields
              %i[reader_lifecycle_factory terminal_session background_worker_builder]
            end
          end
        end
      end
    end
  end
end
