# frozen_string_literal: true

module Shoko
  module Presentation::Ui
    module Constants
      # Text highlighting patterns used by reading renderers.
      module Highlighting
        HIGHLIGHT_WORDS = [
          'Chinese poets', 'philosophers', 'Taoyuen-ming', 'celebrated', 'fragrance',
          'plum-blossoms', 'Linwosing', 'Chowmushih'
        ].freeze
        HIGHLIGHT_PATTERNS = Regexp.union(HIGHLIGHT_WORDS)
        # Matches basic quoted spans for optional highlighting. Supports:
        # - ASCII quotes: "..." and '...'
        # - Curly quotes: “...” and ‘...’
        # - Guillemets: «...» and ‹...›
        QUOTE_PATTERNS = /(["“„«‹][^"“”„«»‹›]*["”»›])|(['‘‚][^'‘’‚]*['’])/
      end
    end
  end
end
