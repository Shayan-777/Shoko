# frozen_string_literal: true

module Shoko
  module Core
    module Models
      module Session
        DISPLAY_CAPABILITIES_SNAPSHOT_FIELDS = %i[kitty_images_enabled].freeze

        # Immutable display capability snapshot for reader/runtime flows.
        DisplayCapabilitiesSnapshot = Data.define(*DISPLAY_CAPABILITIES_SNAPSHOT_FIELDS) do
          def self.build(kitty_images_enabled:)
            new(kitty_images_enabled: kitty_images_enabled == true)
          end

          def kitty_images_enabled?(_state_or_config = nil)
            kitty_images_enabled == true
          end
        end
      end
    end
  end
end
