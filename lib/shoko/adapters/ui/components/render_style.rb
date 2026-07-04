# frozen_string_literal: true

require 'shoko/core/models/block_type'
require_relative '../constants/themes'
require_relative '../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        # Small helper for composing styled strings and common UI elements.
        module RenderStyle
          DEFAULT_PALETTE = Shoko::Adapters::Ui::Constants::Themes::DEFAULT_PALETTE

          SUPERSCRIPT_MAP = {
            '0' => '⁰', '1' => '¹', '2' => '²', '3' => '³', '4' => '⁴',
            '5' => '⁵', '6' => '⁶', '7' => '⁷', '8' => '⁸', '9' => '⁹',
            '+' => '⁺', '-' => '⁻', '=' => '⁼', '(' => '⁽', ')' => '⁾',
            'a' => 'ᵃ', 'b' => 'ᵇ', 'c' => 'ᶜ', 'd' => 'ᵈ', 'e' => 'ᵉ',
            'f' => 'ᶠ', 'g' => 'ᵍ', 'h' => 'ʰ', 'i' => 'ⁱ', 'j' => 'ʲ',
            'k' => 'ᵏ', 'l' => 'ˡ', 'm' => 'ᵐ', 'n' => 'ⁿ', 'o' => 'ᵒ',
            'p' => 'ᵖ', 'r' => 'ʳ', 's' => 'ˢ', 't' => 'ᵗ', 'u' => 'ᵘ',
            'v' => 'ᵛ', 'w' => 'ʷ', 'x' => 'ˣ', 'y' => 'ʸ', 'z' => 'ᶻ',
            ' ' => ' '
          }.freeze

          SUBSCRIPT_MAP = {
            '0' => '₀', '1' => '₁', '2' => '₂', '3' => '₃', '4' => '₄',
            '5' => '₅', '6' => '₆', '7' => '₇', '8' => '₈', '9' => '₉',
            '+' => '₊', '-' => '₋', '=' => '₌', '(' => '₍', ')' => '₎',
            'a' => 'ₐ', 'e' => 'ₑ', 'h' => 'ₕ', 'i' => 'ᵢ', 'j' => 'ⱼ',
            'k' => 'ₖ', 'l' => 'ₗ', 'm' => 'ₘ', 'n' => 'ₙ', 'o' => 'ₒ',
            'p' => 'ₚ', 'r' => 'ᵣ', 's' => 'ₛ', 't' => 'ₜ', 'u' => 'ᵤ',
            'v' => 'ᵥ', 'x' => 'ₓ', ' ' => ' '
          }.freeze

          SMALL_CAPS_MAP = {
            'a' => 'ᴀ', 'b' => 'ʙ', 'c' => 'ᴄ', 'd' => 'ᴅ', 'e' => 'ᴇ',
            'f' => 'ꜰ', 'g' => 'ɢ', 'h' => 'ʜ', 'i' => 'ɪ', 'j' => 'ᴊ',
            'k' => 'ᴋ', 'l' => 'ʟ', 'm' => 'ᴍ', 'n' => 'ɴ', 'o' => 'ᴏ',
            'p' => 'ᴘ', 'q' => 'ǫ', 'r' => 'ʀ', 's' => 'ꜱ', 't' => 'ᴛ',
            'u' => 'ᴜ', 'v' => 'ᴠ', 'w' => 'ᴡ', 'x' => 'x', 'y' => 'ʏ',
            'z' => 'ᴢ'
          }.freeze

          # Book-specified colors are mapped onto the 256-color cube; fully
          # unreadable extremes (near-black/near-white foregrounds without an
          # explicit background) are dropped rather than rendered blind.
          NAMED_COLORS = {
            'black' => [0, 0, 0], 'white' => [255, 255, 255], 'red' => [205, 49, 49],
            'green' => [13, 128, 64], 'blue' => [36, 114, 200], 'yellow' => [229, 190, 20],
            'cyan' => [17, 168, 205], 'magenta' => [188, 63, 188], 'gray' => [128, 128, 128],
            'grey' => [128, 128, 128], 'silver' => [192, 192, 192], 'maroon' => [128, 0, 0],
            'olive' => [128, 128, 0], 'lime' => [0, 205, 0], 'aqua' => [17, 168, 205],
            'teal' => [0, 128, 128], 'navy' => [0, 0, 128], 'fuchsia' => [188, 63, 188],
            'purple' => [128, 0, 128], 'orange' => [230, 126, 34], 'brown' => [141, 84, 44],
            'darkred' => [139, 0, 0], 'darkgreen' => [0, 100, 0], 'darkblue' => [0, 0, 139],
            'crimson' => [220, 20, 60], 'indigo' => [75, 0, 130], 'gold' => [212, 175, 55]
          }.freeze

          @palette = DEFAULT_PALETTE.dup

          class << self
            def configure(palette)
              @palette = DEFAULT_PALETTE.merge(palette || {})
            end

            def palette
              @palette || DEFAULT_PALETTE
            end

            def color(key)
              palette[key] || DEFAULT_PALETTE[key]
            end

            def primary(text)
              color(:primary) + text.to_s + Shoko::Shared::Terminal::Ansi::RESET
            end

            def accent(text)
              color(:accent) + text.to_s + Shoko::Shared::Terminal::Ansi::RESET
            end

            def dim(text)
              color(:dim) + text.to_s + Shoko::Shared::Terminal::Ansi::RESET
            end

            def selection_pointer
              Shoko::Adapters::Ui::Constants::Ui::SELECTION_POINTER
            end

            def selection_pointer_colored
              color(:accent) + selection_pointer + Shoko::Shared::Terminal::Ansi::RESET
            end

            def styled_segment(text, styles = {}, metadata: {})
              content = transform_inline_content(text.to_s, styles)
              return content if content.empty?

              block_type = canonical_block_type(metadata)
              codes = segment_codes(styles, block_type, highlight_enabled?(metadata))
              codes.join + content + Shoko::Shared::Terminal::Ansi::RESET
            end

            private

            def highlight_enabled?(metadata)
              metadata.key?(:highlight_enabled) ? metadata[:highlight_enabled] : true
            end

            def transform_inline_content(content, styles)
              content = transform_vertical_position(content, styles)
              return content unless styles[:small_caps]

              content.each_char.map { |char| SMALL_CAPS_MAP[char] || char }.join
            end

            def transform_vertical_position(content, styles)
              return content unless styles[:superscript] || styles[:subscript]

              map = styles[:superscript] ? SUPERSCRIPT_MAP : SUBSCRIPT_MAP
              content.each_char.map do |char|
                map[char] || map[char.downcase] || char
              end.join
            end

            def canonical_block_type(metadata)
              return nil unless metadata

              raw = metadata[:block_type]
              Shoko::Core::Models::BlockType.canonical(raw) || raw
            end

            def segment_codes(styles, block_type, highlight_allowed)
              [
                color_for(styles, block_type, highlight_allowed),
                background_code(styles, block_type),
                bold_code(styles, block_type),
                italic_code(styles, block_type),
                underline_code(styles),
                strike_code(styles),
                dim_code(styles),
              ].compact
            end

            def bold_code(styles, block_type)
              return Shoko::Shared::Terminal::Ansi::BOLD if styles[:bold] || styles[:large]

              Shoko::Shared::Terminal::Ansi::BOLD if block_type == :heading
            end

            def italic_code(styles, block_type)
              Shoko::Shared::Terminal::Ansi::ITALIC if styles[:italic] || styles[:quote] || block_type == :quote
            end

            def underline_code(styles)
              Shoko::Shared::Terminal::Ansi::UNDERLINE if styles[:underline] || styles[:link_hover]
            end

            def strike_code(styles)
              Shoko::Shared::Terminal::Ansi::STRIKETHROUGH if styles[:strikethrough] || styles[:strike]
            end

            def dim_code(styles)
              Shoko::Shared::Terminal::Ansi::DIM if styles[:prefix] || styles[:dim] || styles[:small]
            end

            def color_for(styles, block_type, highlight_allowed)
              custom = custom_foreground_code(styles)
              return custom if custom

              color(color_key_for(styles, block_type, highlight_allowed))
            end

            def color_key_for(styles, block_type, highlight_allowed)
              inline_color_key(styles) || block_color_key(block_type, styles, highlight_allowed) || :primary
            end

            def inline_color_key(styles)
              return :link if link_style?(styles)
              return :code if styles[:code]
              return :accent if styles[:accent] || styles[:highlight] || styles[:keyword]
              return :prefix if styles[:prefix]

              nil
            end

            def block_color_key(block_type, styles, highlight_allowed)
              return :code if block_type == :code
              return highlight_key(:heading, highlight_allowed) if block_type == :heading
              return highlight_key(:quote, highlight_allowed) if block_type == :quote || styles[:quote]
              return :separator if block_type == :separator

              nil
            end

            def highlight_key(color_name, highlight_allowed)
              highlight_allowed ? color_name : :primary
            end

            def link_style?(styles)
              href = styles[:link]
              !href.nil? && !href.to_s.empty?
            end

            def custom_foreground_code(styles)
              rgb = css_color_to_rgb(styles[:fg])
              return nil unless rgb
              return nil if styles[:bg].nil? && extreme_luminance?(rgb)

              "\e[38;5;#{rgb_to_ansi256(rgb)}m"
            end

            def background_code(styles, block_type = nil)
              rgb = css_color_to_rgb(styles[:bg])
              return "\e[48;5;#{rgb_to_ansi256(rgb)}m" if rgb

              palette[:code_bg] if styles[:code] || block_type == :code
            end

            def css_color_to_rgb(value)
              text = value.to_s.strip.downcase
              return nil if text.empty?
              return hex_to_rgb(text) if text.start_with?('#')
              return rgb_function_to_rgb(text) if text.start_with?('rgb')

              NAMED_COLORS[text]
            end

            def hex_to_rgb(text)
              digits = text.delete_prefix('#')
              case digits.length
              when 3 then digits.chars.map { |c| (c * 2).to_i(16) }
              when 6 then digits.scan(/../).map { |pair| pair.to_i(16) }
              end
            end

            def rgb_function_to_rgb(text)
              numbers = text.scan(/\d+/).first(3).map(&:to_i)
              numbers.length == 3 ? numbers.map { |n| n.clamp(0, 255) } : nil
            end

            def extreme_luminance?(rgb)
              luminance = ((0.2126 * rgb[0]) + (0.7152 * rgb[1]) + (0.0722 * rgb[2])) / 255.0
              luminance < 0.08 || luminance > 0.92
            end

            def rgb_to_ansi256(rgb)
              red, green, blue = rgb
              return grayscale_ansi256(red) if (red - green).abs < 8 && (green - blue).abs < 8

              16 + (36 * scale_to_cube(red)) + (6 * scale_to_cube(green)) + scale_to_cube(blue)
            end

            def scale_to_cube(component)
              return 0 if component < 48
              return 1 if component < 115

              ((component - 35) / 40).clamp(0, 5)
            end

            def grayscale_ansi256(component)
              return 16 if component < 8
              return 231 if component > 238

              232 + ((component - 8) / 10).clamp(0, 23)
            end
          end
        end
      end
    end
  end
end
