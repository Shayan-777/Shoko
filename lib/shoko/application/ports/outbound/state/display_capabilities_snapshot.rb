# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        module State
          # Immutable display-capability snapshot for reader/runtime flows.
          # Returned by the reader runtime-context port to expose terminal
          # capabilities (currently: whether inline images are usable).
          DisplayCapabilitiesSnapshot = Data.define(:kitty_images_enabled) do
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
end
