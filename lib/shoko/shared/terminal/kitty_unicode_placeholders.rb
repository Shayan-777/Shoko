# frozen_string_literal: true

module Shoko
  module Shared
    module Terminal
      # Helpers for emitting Kitty Unicode image placeholders (U+10EEEE) with diacritics.
      # See: https://sw.kovidgoyal.net/kitty/graphics-protocol/#unicode-placeholders
      module KittyUnicodePlaceholders
        module_function

        PLACEHOLDER_CHAR = "\u{10EEEE}"
        RESET_FG = "\e[39m"
        RESET_UNDERLINE = "\e[59m"
        DIACRITIC_CODEPOINTS_PATH = ::File.join(__dir__, 'kitty_unicode_placeholders_diacritic_codepoints.txt')

        def line(image_id:, grid:, placement_id: nil)
          key = cache_key(image_id, grid, placement_id)
          return '' unless key

          cache = (@line_cache ||= {})
          cache.fetch(key) { cache[key] = render_line(key) }
        end

        def diacritics
          @diacritics ||= build_diacritics
        end

        def foreground(image_id)
          rgb_sgr(image_id, sgr: 38, cache: (@fg_cache ||= {}))
        end

        def underline(placement_id)
          rgb_sgr(placement_id, sgr: 58, cache: (@ul_cache ||= {}))
        end

        def build_diacritics
          codepoints = load_diacritic_codepoints
          loaded = codepoints.map { |hex| [Integer(hex, 16)].pack('U') }.freeze
          raise ArgumentError, 'not enough diacritics to support Kitty placeholders' if loaded.length < 256

          loaded
        end

        def cache_key(image_id, grid, placement_id)
          image_i = positive_integer(image_id)
          grid_i = valid_grid(grid)
          return unless image_i && grid_i

          placement_i = (integer_or_nil(placement_id) || 0).clamp(0, 0xFF_FF_FF)
          (image_i << 40) | (placement_i << 16) | grid_i
        end

        def integer_or_nil(value)
          Integer(value)
        rescue ArgumentError, TypeError
          raise
        end

        def load_diacritic_codepoints
          ::File.read(DIACRITIC_CODEPOINTS_PATH, encoding: Encoding::UTF_8).split
        end

        def positive_integer(value)
          int = integer_or_nil(value)
          return unless int&.positive?

          int & 0xFFFF_FFFF
        end

        def valid_grid(value)
          grid_i = integer_or_nil(value)
          return unless grid_i && (0..0xFFFF).cover?(grid_i) && (1..255).cover?(grid_i & 0xFF)

          grid_i
        end

        def placeholder_cells(key)
          marks = diacritics
          cols = key & 0xFF
          first = PLACEHOLDER_CHAR + marks.fetch((key >> 8) & 0xFF) + marks.fetch(0) + msb_diacritic(marks, key)
          first + (cols > 1 ? (PLACEHOLDER_CHAR * (cols - 1)) : '')
        end

        def msb_diacritic(marks, key)
          msb = (key >> 64) & 0xFF
          msb.zero? ? '' : marks.fetch(msb)
        end

        def render_line(key)
          cells = placeholder_cells(key)
          wrap_sequences(key, cells)
        end

        def wrap_sequences(key, cells)
          image_id = (key >> 40) & 0xFFFF_FFFF
          placement_id = (key >> 16) & 0xFF_FF_FF
          fg = foreground(image_id)

          return "#{fg}#{cells}#{RESET_FG}" unless placement_id.positive?

          "#{fg}#{underline(placement_id)}#{cells}#{RESET_FG}#{RESET_UNDERLINE}"
        end

        def rgb_sgr(value, sgr:, cache:)
          bits = integer_or_nil(value)
          return '' unless bits

          bits &= 0xFF_FF_FF
          cache.fetch(bits) { cache[bits] = build_rgb_sgr(sgr, bits) }
        end

        def build_rgb_sgr(sgr, bits)
          red = (bits >> 16) & 0xFF
          green = (bits >> 8) & 0xFF
          blue = bits & 0xFF
          "\e[#{sgr};2;#{red};#{green};#{blue}m"
        end

        private_class_method :build_diacritics,
                             :build_rgb_sgr,
                             :cache_key,
                             :diacritics,
                             :foreground,
                             :integer_or_nil,
                             :load_diacritic_codepoints,
                             :msb_diacritic,
                             :placeholder_cells,
                             :positive_integer,
                             :render_line,
                             :rgb_sgr,
                             :underline,
                             :valid_grid,
                             :wrap_sequences
      end
    end
  end
end
