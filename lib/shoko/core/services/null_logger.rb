# frozen_string_literal: true

module Shoko
  module Core
    module Services
      # A no-op logger implementation for tests and when logging is disabled.
      class NullLogger
        def debug(_message, **_metadata)
          # No-op
        end

        def info(_message, **_metadata)
          # No-op
        end

        def warn(_message, **_metadata)
          # No-op
        end

        def error(_message, **_metadata)
          # No-op
        end

        def fatal(_message, **_metadata)
          # No-op
        end

        def with_context(_context)
          yield if block_given?
        end
      end
    end
  end
end
