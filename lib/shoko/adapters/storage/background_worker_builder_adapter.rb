# frozen_string_literal: true

require_relative '../../core/ports/outbound/background_worker_builder'
require_relative '../../core/ports/outbound/logging'
require_relative 'background_worker'

module Shoko
  module Adapters
    module Storage
      # Adapter that constructs background worker instances for runtime workflows.
      class BackgroundWorkerBuilderAdapter
        include Shoko::Core::Ports::Outbound::BackgroundWorkerBuilder

        def build(name:, logger:)
          unless logger.nil? || logger.is_a?(Shoko::Core::Ports::Outbound::Logging)
            raise ArgumentError, 'logger must implement Core::Ports::Outbound::Logging when provided'
          end

          Shoko::Adapters::Storage::BackgroundWorker.new(name: name, logger: logger)
        end
      end
    end
  end
end
