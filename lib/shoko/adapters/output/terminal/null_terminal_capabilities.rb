# frozen_string_literal: true

require_relative '../../../core/ports/outbound/terminal_capabilities'

module Shoko
  module Adapters
    module Output
      module Terminal
        # Conservative terminal capabilities used for tests and headless runs.
        class NullTerminalCapabilities
          include Shoko::Core::Ports::Outbound::TerminalCapabilities

          def kitty_graphics_supported?
            false
          end
        end
      end
    end
  end
end
