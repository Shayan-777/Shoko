# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port interface for timing and tracing instrumentation.
        module Instrumentation
          # Measure a block of work.
          #
          # @param metric [String] metric label
          # @return [Object] block result
          def measure(_metric, &)
            raise NotImplementedError, "#{self.class} must implement #measure"
          end

          # Alias to #measure for callers expecting #time.
          def time(metric, &)
            measure(metric, &)
          end

          # Attach metadata to the active trace.
          #
          # @param payload [Hash]
          # @return [void]
          def annotate(_payload)
            raise NotImplementedError, "#{self.class} must implement #annotate"
          end
        end
      end
    end
  end
end
