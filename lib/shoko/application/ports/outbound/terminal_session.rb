# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Runtime boundary for terminal session lifecycle operations.
        module TerminalSession
          def setup
            raise NotImplementedError, "#{self.class} must implement #setup"
          end

          def cleanup
            raise NotImplementedError, "#{self.class} must implement #cleanup"
          end

          def size
            raise NotImplementedError, "#{self.class} must implement #size"
          end
        end
      end
    end
  end
end
