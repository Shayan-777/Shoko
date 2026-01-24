# frozen_string_literal: true

module Shoko
  module Adapters
    # Base class for adapters in the hexagonal architecture.
    # Adapters connect ports to external infrastructure (UI, databases, etc.)
    # and should NOT extend Core's BaseService.
    #
    # This class provides a simple dependency injection pattern via constructor kwargs
    # without the `resolve()` semantics of BaseService.
    class BaseAdapter
      # @param logger [Object, nil] Optional logger for debugging
      def initialize(logger: nil)
        @logger = logger
      end

      protected

      attr_reader :logger

      def log_debug(message, **context)
        logger&.debug(message, **context)
      end

      def log_error(message, **context)
        logger&.error(message, **context)
      end
    end
  end
end
