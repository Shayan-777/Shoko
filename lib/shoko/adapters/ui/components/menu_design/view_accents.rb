# frozen_string_literal: true

require_relative '../status_bar/palette'

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # Signature accent per menu view — the same accent the view's closest
          # in-book relative carries, so the whole menu and the bar-anchored
          # reader panels speak one color language: amber for searching the
          # shelf, cyan for external lookup, lavender for feeds/navigation,
          # emerald for translation, brand blue for the shelf and notes.
          module ViewAccents
            Palette = StatusBar::Palette

            BY_KEY = {
              browse: Palette::LIST_MATCH_FG,        # amber — the search family
              library: Palette::LIST_POINTER_FG,     # brand blue — the shelf
              annotations: Palette::NOTES_ACCENT_FG, # notes stay brand blue
              rss_reader: Palette::TOC_CURRENT_FG,   # lavender — navigation
              download: Palette::DICT_HEADWORD_FG,   # cyan — external lookup
              dictionary: Palette::DICT_HEADWORD_FG, # cyan — the dictionary itself
              translator: Palette::TRANS_ACCENT_FG,  # emerald — the translator
              settings: Palette::LANDING_TEXT_FG,    # neutral slate
              quit: Palette::LANDING_QUIT_FG,        # soft red
            }.freeze

            module_function

            def for(key)
              BY_KEY.fetch(key, Palette::LANDING_TEXT_FG)
            end
          end
        end
      end
    end
  end
end
