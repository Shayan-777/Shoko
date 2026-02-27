# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      # Immutable visual-profile data passed from composition to menu components.
      MenuVisualProfile = Data.define(:color_mode, :ascii_icons)
    end
  end
end
