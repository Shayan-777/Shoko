# frozen_string_literal: true

require_relative '../ports/outbound/display_capabilities'

module Shoko
  module Core
    module Services
      # Default display capabilities (no optional features enabled).
      class DefaultDisplayCapabilities
        include Core::Ports::Outbound::DisplayCapabilities

        def kitty_images_enabled?(_state_or_config)
          false
        end
      end
    end
  end
end
