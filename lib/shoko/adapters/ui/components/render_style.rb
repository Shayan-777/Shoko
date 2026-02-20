# frozen_string_literal: true

module Shoko
  module Adapters::Ui::Components
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

          codes = []
          block_type = metadata && metadata[:block_type]
          highlight_allowed = metadata.key?(:highlight_enabled) ? metadata[:highlight_enabled] : true

          color_code = color_for(styles, block_type, highlight_allowed)
          codes << color_code if color_code

          codes << Shoko::Shared::Terminal::Ansi::BOLD if styles[:bold] || block_type == :heading
          codes << Shoko::Shared::Terminal::Ansi::ITALIC if styles[:italic] || styles[:quote] || block_type == :quote
          codes << Shoko::Shared::Terminal::Ansi::UNDERLINE if styles[:underline]
          codes << Shoko::Shared::Terminal::Ansi::STRIKETHROUGH if styles[:strikethrough] || styles[:strike]
          codes << Shoko::Shared::Terminal::Ansi::DIM if styles[:prefix] || styles[:dim]

          codes.join + content + Shoko::Shared::Terminal::Ansi::RESET
        end

        private

        def transform_inline_position(content, styles)
          return content unless styles[:superscript] || styles[:subscript]

          map = styles[:superscript] ? SUPERSCRIPT_MAP : SUBSCRIPT_MAP
          content.each_char.map do |char|
            map[char] || map[char.downcase] || char
          end.join
        end

        def color_for(styles, block_type, highlight_allowed)
          if styles[:code] || block_type == :code
            color(:code)
          elsif styles[:accent] || styles[:highlight] || styles[:keyword]
            color(:accent)
          elsif block_type == :heading
            highlight_allowed ? color(:heading) : color(:primary)
          elsif block_type == :quote || styles[:quote]
            highlight_allowed ? color(:quote) : color(:primary)
          elsif block_type == :separator
            color(:separator)
          elsif styles[:prefix]
            color(:prefix)
          else
            color(:primary)
          end
        end
      end
    end
  end
end
