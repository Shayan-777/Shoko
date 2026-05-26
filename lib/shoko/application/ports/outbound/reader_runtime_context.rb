# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port interface exposing runtime-only reader context like terminal size
        # and computed display capabilities.
        module ReaderRuntimeContext
          def terminal_size
            raise NotImplementedError, "#{self.class} must implement #terminal_size"
          end

          def display_capabilities
            raise NotImplementedError, "#{self.class} must implement #display_capabilities"
          end
        end
      end
    end
  end
end
