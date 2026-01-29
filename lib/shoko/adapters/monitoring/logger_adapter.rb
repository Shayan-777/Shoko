# frozen_string_literal: true

require_relative '../../core/ports/logging'
require_relative 'logger'

module Shoko
  module Adapters
    module Monitoring
      # Instance-based adapter that implements the Logging port.
      # Delegates to the static Logger class for actual logging.
      # This allows logger to be injected via DI for testability.
      class LoggerAdapter
        include Core::Ports::Logging

        def initialize(level: nil, output: nil)
          @level = level
          @output = output
          configure_static_logger
        end

        def debug(message, **metadata)
          Logger.debug(message, **metadata)
        end

        def info(message, **metadata)
          Logger.info(message, **metadata)
        end

        def warn(message, **metadata)
          Logger.warn(message, **metadata)
        end

        def error(message, **metadata)
          Logger.error(message, **metadata)
        end

        def fatal(message, **metadata)
          Logger.fatal(message, **metadata)
        end

        def with_context(context, &)
          Logger.with_context(context, &)
        end

        # Accessors for configuration
        def level
          @level || Logger.level
        end

        def level=(new_level)
          @level = new_level
          Logger.level = new_level
        end

        def output
          @output || Logger.output
        end

        def output=(new_output)
          @output = new_output
          Logger.output = new_output
        end

        private

        def configure_static_logger
          Logger.level = @level if @level
          Logger.output = @output if @output
        end
      end
    end
  end
end
