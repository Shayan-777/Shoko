# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for detecting terminal hardware capabilities.
      # Abstracts the detection of terminal features like Kitty graphics protocol,
      # separating hardware detection from configuration state.
      #
      # Note: This is distinct from DisplayCapabilities which checks if features
      # are ENABLED in configuration. TerminalCapabilities detects if the
      # terminal SUPPORTS the features at a hardware/protocol level.
      #
      # @example Implementing this port
      #   class TerminalCapabilitiesAdapter
      #     include Shoko::Core::Ports::TerminalCapabilities
      #
      #     def kitty_graphics_supported?
      #       ENV.key?('KITTY_WINDOW_ID')
      #     end
      #   end
      module TerminalCapabilities
        # Check if the terminal supports Kitty graphics protocol.
        # This is a hardware/environment detection, not a config check.
        #
        # @return [Boolean] True if Kitty graphics are supported
        def kitty_graphics_supported?
          raise NotImplementedError, "#{self.class} must implement #kitty_graphics_supported?"
        end
      end
    end
  end
end
