# frozen_string_literal: true

require 'shoko/application/ports/outbound/display_capabilities'
require_relative 'kitty_graphics'

module Shoko
  module Adapters
    module Output
      module Kitty
        # Adapter providing display capability checks for core ports.
        class DisplayCapabilities
          include Shoko::Application::Ports::Outbound::DisplayCapabilities

          def kitty_images_enabled?(state_or_config)
            KittyGraphics.enabled_for?(state_or_config)
          end
        end
      end
    end
  end
end
