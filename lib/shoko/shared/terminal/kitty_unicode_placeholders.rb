# frozen_string_literal: true

require_relative '../../adapters/output/kitty/kitty_unicode_placeholders'

module Shoko
  module Shared
    module Terminal
      # Shared alias for kitty unicode placeholder generation.
      KittyUnicodePlaceholders = Shoko::Adapters::Output::Kitty::KittyUnicodePlaceholders
    end
  end
end
