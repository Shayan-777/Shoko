# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      class BookCachePipeline
        # Raises standardized load errors for pipeline failures.
        class LoadErrorHandler
          def initialize(path, logger: nil)
            @path = path
            @logger = logger
          end

          def call(error)
            message = error.message
            @logger&.error('Book cache pipeline failed', path: @path, error: message)
            raise Shoko::BookParseError.new(message, @path)
          end
        end

        private_constant :LoadErrorHandler
      end
    end
  end
end
