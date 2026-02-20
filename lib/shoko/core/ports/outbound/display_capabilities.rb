# frozen_string_literal: true

module Shoko
  module Core
    module Ports::Outbound
      # Port interface for display feature detection (e.g., kitty images).
      module DisplayCapabilities
        # Return true when kitty images are enabled for the given config/state.
        #
        # @param state_or_config [Object]
        # @return [Boolean]
        def kitty_images_enabled?(_state_or_config)
          raise NotImplementedError, "#{self.class} must implement #kitty_images_enabled?"
        end
      end
    end
  end
end
