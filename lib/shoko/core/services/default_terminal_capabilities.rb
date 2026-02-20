# frozen_string_literal: true

require_relative '../ports/outbound/terminal_capabilities'

module Shoko
  module Core
    module Services
      # Default implementation of TerminalCapabilities port for core layer use.
      # Returns false for all capabilities, safe for testing and headless environments.
      class DefaultTerminalCapabilities
        include Ports::Outbound::TerminalCapabilities

        # Check if the terminal supports Kitty graphics protocol.
        # Default implementation returns false (conservative default).
        #
        # @return [Boolean] Always returns false
        def kitty_graphics_supported?
          false
        end
      end
    end
  end
end
