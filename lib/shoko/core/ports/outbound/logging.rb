# frozen_string_literal: true

module Shoko
  module Core
    module Ports::Outbound
      # Port interface for logging operations.
      # Implementations can write to stderr, files, or be null loggers for tests.
      module Logging
        # Log a debug message.
        #
        # @param message [String] The log message
        # @param metadata [Hash] Additional contextual data
        # @return [void]
        def debug(_message, **_metadata)
          raise NotImplementedError, "#{self.class} must implement #debug"
        end

        # Log an info message.
        #
        # @param message [String] The log message
        # @param metadata [Hash] Additional contextual data
        # @return [void]
        def info(_message, **_metadata)
          raise NotImplementedError, "#{self.class} must implement #info"
        end

        # Log a warning message.
        #
        # @param message [String] The log message
        # @param metadata [Hash] Additional contextual data
        # @return [void]
        def warn(_message, **_metadata)
          raise NotImplementedError, "#{self.class} must implement #warn"
        end

        # Log an error message.
        #
        # @param message [String] The log message
        # @param metadata [Hash] Additional contextual data
        # @return [void]
        def error(_message, **_metadata)
          raise NotImplementedError, "#{self.class} must implement #error"
        end

        # Log a fatal message.
        #
        # @param message [String] The log message
        # @param metadata [Hash] Additional contextual data
        # @return [void]
        def fatal(_message, **_metadata)
          raise NotImplementedError, "#{self.class} must implement #fatal"
        end

        # Execute a block with added context.
        #
        # @param context [Hash] Context to add for the duration of the block
        # @yield Block to execute with the added context
        # @return [Object] The block's return value
        def with_context(_context)
          raise NotImplementedError, "#{self.class} must implement #with_context"
        end
      end
    end
  end
end
