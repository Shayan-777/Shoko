# frozen_string_literal: true

require 'monitor'

module Shoko
  module Adapters
    module Ui
      # Lightweight registry for per-frame render metadata (rendered line geometry).
      # This keeps large, frequently-updated hashes out of the global state store.
      class RenderRegistry
        class << self
          # Replace the global instance (used by tests).
          def install(instance)
            @current = instance
          end
        end

        def initialize
          @monitor = Monitor.new
          @rendered_lines = {}
        end

        def write(lines)
          return unless lines

          @monitor.synchronize do
            # Store the hash directly; callers control lifecycle per-frame.
            @rendered_lines = lines
          end
        end

        def clear
          @monitor.synchronize { @rendered_lines = {} }
        end

        def lines
          @monitor.synchronize { @rendered_lines }
        end
      end
    end
  end
end
