# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Shared reader layout/formatting defaults used across application and UI layers.
      module ReaderSettings
        DEFAULT_LINE_SPACING = :normal
        LINE_SPACING_VALUES = %i[compact normal relaxed].freeze
        LINE_SPACING_MULTIPLIERS = { compact: 1.0, normal: 0.75, relaxed: 0.5 }.freeze

        DEFAULT_PARAGRAPH_STYLE = :book
        PARAGRAPH_STYLE_VALUES = %i[book spaced indent].freeze

        DEFAULT_JUSTIFY = :book
        JUSTIFY_VALUES = %i[book on off].freeze

        SINGLE_VIEW_WIDTH_PERCENT = 0.9
      end
    end
  end
end
