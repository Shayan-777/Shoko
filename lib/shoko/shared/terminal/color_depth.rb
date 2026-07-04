# frozen_string_literal: true

module Shoko
  module Shared
    module Terminal
      # Detects how much color the hosting terminal supports. Truecolor is
      # advertised via COLORTERM by every modern emulator; a few well-known
      # TERM values imply it too. SHOKO_TRUECOLOR=1/0 forces the answer.
      module ColorDepth
        TRUECOLOR_TERM_PATTERN = /kitty|wezterm|foot|alacritty|ghostty|direct|iterm/i

        module_function

        def truecolor?(env: ENV)
          override = env['SHOKO_TRUECOLOR']
          return override == '1' if %w[0 1].include?(override)

          return true if /truecolor|24bit/i.match?(env['COLORTERM'].to_s)

          TRUECOLOR_TERM_PATTERN.match?(env['TERM'].to_s) ||
            TRUECOLOR_TERM_PATTERN.match?(env['TERM_PROGRAM'].to_s)
        end
      end
    end
  end
end
