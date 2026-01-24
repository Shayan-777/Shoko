# frozen_string_literal: true

require_relative '../../core/ports/terminal_capabilities'
require_relative 'kitty/kitty_graphics'

module Shoko
  module Adapters
    module Output
      # Adapter implementing the TerminalCapabilities port.
      # Wraps KittyGraphics for terminal feature detection.
      class TerminalCapabilitiesAdapter
        include Core::Ports::TerminalCapabilities

        # Check if the terminal supports Kitty graphics protocol.
        #
        # @return [Boolean] True if Kitty graphics are supported
        def kitty_graphics_supported?
          Kitty::KittyGraphics.supported?
        end
      end
    end
  end
end
