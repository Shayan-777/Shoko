# frozen_string_literal: true

module Shoko
  module Core
    module Ports::Outbound
      # Port interface for background execution.
      module AsyncExecutor
        # Submit work for background execution.
        #
        # @yield Block to execute
        def submit(&)
          raise NotImplementedError, "#{self.class} must implement #submit"
        end

        # Shut down the executor.
        #
        # @param timeout [Numeric,nil]
        def shutdown(_timeout = nil)
          raise NotImplementedError, "#{self.class} must implement #shutdown"
        end
      end
    end
  end
end
