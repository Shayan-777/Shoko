# frozen_string_literal: true

require_relative '../../core/ports/outbound/display_capabilities'

module Shoko
  module Adapters
    module Output
      # Display capabilities with all optional features disabled.
      class NullDisplayCapabilities
        include Shoko::Core::Ports::Outbound::DisplayCapabilities

        def kitty_images_enabled?(_state_or_config)
          false
        end
      end
    end
  end
end
