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
            LIST_HOVER_BG = "\e[48;2;51;64;88m" # mouse-hover preview (midway to the selection)
            LIST_RULE_FG = "\e[38;2;70;77;100m"    # top edge of the panel
            LIST_TEXT_FG = "\e[38;2;205;212;236m"  # snippet text
            LIST_DIM_FG = "\e[38;2;132;139;164m"   # location / secondary
            LIST_MATCH_FG = "\e[38;2;245;200;120m" # the matched term (amber)
            LIST_POINTER_FG = "\e[38;2;137;180;250m"
            LIST_SCROLL_TRACK_FG = "\e[38;2;158;164;186m" # full-height scrollbar track (lighter)
            LIST_SCROLL_THUMB_FG = "\e[38;2;96;142;236m"  # scrollbar thumb / wheel (deeper accent)

            # Dictionary "Definition card" — shares the search list's slate surface
            # so it sits in the same family as the bar, with a soft cyan headword as
            # its only signature accent (vs. the search list's amber match), so the
            # two stay distinguishable without the card reading as a foreign panel.
            DICT_BG = "\e[48;2;44;50;66m"           # elevated slate panel (matches the search list)
            DICT_SELECTED_BG = "\e[48;2;58;78;110m" # highlighted fuzzy candidate row
            DICT_HOVER_BG = "\e[48;2;51;64;88m"     # mouse-hover preview (midway to the selection)
            DICT_RULE_FG = "\e[38;2;70;77;100m"     # top edge of the card
            DICT_HEADWORD_FG = "\e[38;2;130;205;224m" # the looked-up word (soft cyan signature)
            DICT_SENSE_FG = "\e[38;2;205;212;236m"  # sense / definition text
            DICT_NUM_FG = "\e[38;2;137;180;250m"    # numbered sense markers (brand blue)
            DICT_TRANS_FG = "\e[38;2;150;196;224m"  # translations (soft blue-cyan)
            DICT_DIM_FG = "\e[38;2;132;139;164m"    # pair / count / labels (muted blue-gray)
            DICT_POINTER_FG = "\e[38;2;137;180;250m" # fuzzy candidate pointer (brand blue)

            # Table of Contents panel — the third member of the bar-anchored family.
            # Shares the same elevated slate surface as the search list and the
            # dictionary card, so it reads as the same kind of panel. Its signature
            # accent is a soft lavender "you are here" marker (vs. the search list's
            # amber match and the dictionary's cyan headword); the selection pointer
            # stays brand blue, keeping the pointer language consistent across all three.
            TOC_BG = "\e[48;2;44;50;66m"            # elevated slate panel (matches search/dict)
            TOC_SELECTED_BG = "\e[48;2;58;78;110m"  # highlighted row
            TOC_HOVER_BG = "\e[48;2;51;64;88m"      # mouse-hover preview (midway to the selection)
            TOC_RULE_FG = "\e[38;2;70;77;100m"      # top edge of the panel
            TOC_TITLE_FG = "\e[38;2;210;217;240m"   # top-level entry titles
            TOC_SUB_FG = "\e[38;2;156;164;192m"     # nested entry titles (one tone back)
            TOC_FAINT_FG = "\e[38;2;120;128;156m"   # deepest nesting / tree guides
            TOC_DIM_FG = "\e[38;2;132;139;164m"     # count / labels / secondary
            TOC_CURRENT_FG = "\e[38;2;183;162;236m" # current reading position (soft lavender signature)
            TOC_POINTER_FG = "\e[38;2;137;180;250m" # selected-row pointer (brand blue)
            TOC_SCROLL_TRACK_FG = "\e[38;2;158;164;186m" # scrollbar track (lighter)
            TOC_SCROLL_THUMB_FG = "\e[38;2;96;142;236m"  # scrollbar thumb / wheel (deeper accent)

            # Translator card — the fourth member of the bar-anchored family. Shares
            # the same elevated slate surface as the search list, the dictionary card,
            # and the TOC panel, so it reads as the same kind of panel. Its signature
            # accent is a soft emerald (vs. the search list's amber match, the
            # dictionary's cyan headword, and the TOC's lavender marker): it carries the
            # source→target arrow, the translated text, and the active language chip,
            # while the selection pointer stays brand blue — keeping the pointer
            # language consistent across all four panels.
            TRANS_BG = "\e[48;2;40;46;61m"          # the card surface (translation pane)
            TRANS_FIELD_BG = "\e[48;2;52;60;82m"    # the raised source-editor well (the "compose" card)
            TRANS_FIELD_EDGE = "\e[38;2;72;82;112m" # hairline framing the source well
            TRANS_SELECTED_BG = "\e[48;2;58;78;110m" # highlighted language-candidate row
            TRANS_HOVER_BG = "\e[48;2;49;62;86m"     # mouse-hover preview (midway to the selection)
            TRANS_BUTTON_BG = "\e[48;2;52;60;82m"        # filled action button (Paste/Copy) at rest
            TRANS_BUTTON_HOVER_BG = "\e[48;2;62;80;111m" # the button under the pointer
            TRANS_BUTTON_ACTIVE_BG = "\e[48;2;72;100;140m" # the button on click / during its Pasted!/Copied! flash
            TRANS_BUTTON_FG = "\e[38;2;214;236;226m" # the button label (bright, legible on the fill)
            TRANS_TAB_ACTIVE_BG = "\e[48;2;56;66;90m"   # the language tab whose list is open (raised, lit)
            TRANS_TAB_INACTIVE_BG = "\e[48;2;33;38;50m" # the other tab (recessed, sits in the background)
            TRANS_CLOSE_BG = "\e[48;2;176;58;62m"        # the red close (✕) box on the editor rule
            TRANS_CLOSE_HOVER_BG = "\e[48;2;208;74;78m"  # the close box under the pointer (brighter red)
            TRANS_CLOSE_FG = "\e[38;2;250;240;240m"      # the ✕ glyph (bright, legible on red)
            TRANS_RULE_FG = "\e[38;2;72;80;104m"    # hairline rules / dividers
            TRANS_TEXT_FG = "\e[38;2;205;231;216m"  # the translated text (emerald-tinted, primary)
            TRANS_INPUT_FG = "\e[38;2;232;237;248m" # the source text being composed (bright)
            TRANS_PLACEHOLDER_FG = "\e[38;2;128;137;166m" # placeholder in the empty source well
            TRANS_CARET_FG = "\e[38;2;150;230;185m" # the blinking thin-stripe caret (bright emerald)
            TRANS_ACCENT_FG = "\e[38;2;126;211;164m" # source→target arrow + active chip (soft emerald signature)
            TRANS_SOURCE_FG = "\e[38;2;156;164;192m" # the echoed source text (muted)
            TRANS_LANG_FG = "\e[38;2;205;212;236m"  # language names in the picker list
            TRANS_CODE_FG = "\e[38;2;130;205;224m"  # language codes (soft cyan)
            TRANS_DIM_FG = "\e[38;2;132;139;164m"   # pair / count / labels / hints (muted)
            TRANS_POINTER_FG = "\e[38;2;137;180;250m" # selected-candidate pointer (brand blue)
            TRANS_SCROLL_TRACK_FG = "\e[38;2;158;164;186m" # scrollbar track (lighter)
            TRANS_SCROLL_THUMB_FG = "\e[38;2;96;142;236m"  # scrollbar thumb / wheel (deeper accent)

            # Annotation-notes panel — the fifth member of the bar-anchored family.
            # Shares the same elevated slate surface as the search list, the
            # dictionary card, the TOC panel, and the translator, so it reads as the
            # same kind of panel. It deliberately stays in the neutral slate +
            # brand-blue language (the search-style selection bar, the brand-blue
            # compose caret and active labels) rather than taking a coloured signature
            # accent, so nothing reads as off-palette.
            NOTES_BG = "\e[48;2;44;50;66m"            # elevated slate panel (matches family)
            NOTES_FIELD_BG = "\e[48;2;52;60;82m"      # the raised compose-editor well
            NOTES_SELECTED_BG = "\e[48;2;58;78;110m"  # highlighted note row
            NOTES_HOVER_BG = "\e[48;2;51;64;88m"      # mouse-hover preview (midway to the selection)
            NOTES_RULE_FG = "\e[38;2;70;77;100m"      # hairline rules / top edge
            NOTES_NOTE_FG = "\e[38;2;212;217;236m"    # the note text (primary)
            NOTES_EXCERPT_FG = "\e[38;2;150;158;186m" # the highlighted excerpt being annotated (muted)
            NOTES_INPUT_FG = "\e[38;2;232;237;248m"   # the note being composed (bright)
            NOTES_PLACEHOLDER_FG = "\e[38;2;128;137;166m" # placeholder in the empty compose well
            NOTES_MARKUP_FG = "\e[38;2;120;128;156m"  # markup markers (*_-~, bullets) — visible but quiet
            NOTES_CARET_FG = "\e[38;2;137;180;250m"   # the blinking thin-stripe caret (brand blue)
            NOTES_ACCENT_FG = "\e[38;2;137;180;250m"  # active compose labels (brand blue)
            NOTES_DIM_FG = "\e[38;2;132;139;164m"     # location / count / labels / hints (muted)
            NOTES_POINTER_FG = "\e[38;2;137;180;250m" # selected-row selection bar (brand blue)
            NOTES_SCROLL_TRACK_FG = "\e[38;2;158;164;186m" # scrollbar track (lighter)
            NOTES_SCROLL_THUMB_FG = "\e[38;2;96;142;236m"  # scrollbar thumb / wheel (deeper accent)

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
