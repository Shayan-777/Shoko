# frozen_string_literal: true

require_relative '../../../core/models/block_type'
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
            'i' => 'ⁱ', 'n' => 'ⁿ'
          }.freeze

          SUBSCRIPT_MAP = {
            '0' => '₀', '1' => '₁', '2' => '₂', '3' => '₃', '4' => '₄',
            '5' => '₅', '6' => '₆', '7' => '₇', '8' => '₈', '9' => '₉',
            '+' => '₊', '-' => '₋', '=' => '₌', '(' => '₍', ')' => '₎',
            'a' => 'ₐ', 'e' => 'ₑ', 'h' => 'ₕ', 'i' => 'ᵢ', 'j' => 'ⱼ',
            'k' => 'ₖ', 'l' => 'ₗ', 'm' => 'ₘ', 'n' => 'ₙ', 'o' => 'ₒ',
            'p' => 'ₚ', 'r' => 'ᵣ', 's' => 'ₛ', 't' => 'ₜ', 'u' => 'ᵤ',
            'v' => 'ᵥ', 'x' => 'ₓ'
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
              content = transform_inline_position(text.to_s, styles)
              return content if content.empty?

              block_type = canonical_block_type(metadata)
              codes = segment_codes(styles, block_type, highlight_enabled?(metadata))
              codes.join + content + Shoko::Shared::Terminal::Ansi::RESET
            end

            private

            def highlight_enabled?(metadata)
              metadata.key?(:highlight_enabled) ? metadata[:highlight_enabled] : true
            end

            def transform_inline_position(content, styles)
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
                bold_code(styles, block_type),
                italic_code(styles, block_type),
                underline_code(styles),
                strike_code(styles),
                dim_code(styles),
              ].compact
            end

            def bold_code(styles, block_type)
              Shoko::Shared::Terminal::Ansi::BOLD if styles[:bold] || block_type == :heading
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
              Shoko::Shared::Terminal::Ansi::DIM if styles[:prefix] || styles[:dim]
            end

            def color_for(styles, block_type, highlight_allowed)
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
          end
        end
      end
    end
  end
end
