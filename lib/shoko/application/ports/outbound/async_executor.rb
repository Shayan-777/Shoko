# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port interface for background execution.
        module AsyncExecutor
          # Submit work for background execution.
          #
          # @yield Block to execute
          def submit(&)
            raise NotImplementedError, "#{self.class} must implement #submit"
          end

          # Whether submitted work completes on the caller thread. Consumers
          # use this capability instead of identifying a concrete adapter.
          def synchronous?
            false
          end

          # Shut down the executor.
          #
          # @param timeout [Numeric,nil] maximum seconds to wait; nil waits indefinitely
          # Returns only once execution has stopped.
          def shutdown(timeout: nil)
            raise NotImplementedError, "#{self.class} must implement #shutdown"
          end
        end
      end
    end
  end
end
