# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module StatusBar
          # Truecolor tokens for the bottom status bar.
          #
          # The bar is a flat, gently elevated slate strip that reads as a single
          # cohesive surface regardless of the active reader theme. Colors are kept
          # in one place so the badge, progress bar, and composer stay in visual sync.
          module Palette
            RESET = "\e[0m"
            BOLD = "\e[1m"

            # Bar surface and text tones (dark-first; intentionally consistent
            # across light/dark themes, the way editor status bars usually are).
            BAR_BG = "\e[48;2;38;43;56m"          # slate surface
            TITLE_FG = "\e[38;2;226;232;248m"     # near-white, paired with BOLD
            TEXT_FG = "\e[38;2;196;203;226m"      # body text
            DIM_FG = "\e[38;2;124;131;156m"       # secondary / separators
            FAINT_FG = "\e[38;2;86;92;118m"       # unfilled progress groove

            TRACK_BG = "\e[48;2;55;61;80m"        # progress track behind the fill

            # Caret for the in-bar search input (steady block).
            CARET = "\e[38;2;137;180;250m▏"

            # Two-compartment reader badge: a neutral "mode" compartment (Reader /
            # Search) meets the format-colored compartment along a tilted slant.
            BADGE_MODE_RGB = [60, 66, 84].freeze   # slate mode compartment
            BADGE_MODE_FG = "\e[38;2;230;235;250m" # mode label
            BADGE_SLANT = "\u{E0BC}"               # powerline forward slant (◤), the tilted divider

            # In-book search results list (floats above the bar, growing upward).
            LIST_BG = "\e[48;2;44;50;66m" # elevated panel, a touch above the bar
            LIST_SELECTED_BG = "\e[48;2;58;78;110m" # highlighted row
            LIST_RULE_FG = "\e[38;2;70;77;100m"    # top edge of the panel
            LIST_TEXT_FG = "\e[38;2;205;212;236m"  # snippet text
            LIST_DIM_FG = "\e[38;2;132;139;164m"   # location / secondary
            LIST_MATCH_FG = "\e[38;2;245;200;120m" # the matched term (amber)
            LIST_POINTER_FG = "\e[38;2;137;180;250m"

            # Neutral brand accent used by non-reader (menu) views.
            BRAND_RGB = [137, 180, 250].freeze # soft blue

            SEPARATOR = '·'

            module_function

            # Foreground truecolor escape from an [r, g, b] triplet.
            def fg(rgb)
              r, g, b = rgb
              "\e[38;2;#{r};#{g};#{b}m"
            end

            # Background truecolor escape from an [r, g, b] triplet.
            def bg(rgb)
              r, g, b = rgb
              "\e[48;2;#{r};#{g};#{b}m"
            end

            # A span carrying its own complete style. Starting every span with RESET
            # keeps the terminal frame buffer's per-cell style clean (no accumulation),
            # so adjacent spans never inherit one another's color or background.
            def span(text, style)
              "#{RESET}#{BAR_BG}#{style}#{text}"
            end
          end
        end
      end
    end
  end
end
