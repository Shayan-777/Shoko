# frozen_string_literal: true

require_relative '../../../shared/terminal/kitty_unicode_placeholders'

module Shoko
  module Adapters
    module Output
      module Kitty
        # Adapter alias to canonical shared implementation.
        KittyUnicodePlaceholders = Shoko::Shared::Terminal::KittyUnicodePlaceholders
      end
    end
  end
end
