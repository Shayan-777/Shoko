# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Tracks list numbering/marker state for one <ol>/<ul> nesting level,
        # honoring start/value/type attributes and nesting-depth bullets.
        class ListMarker
          ORDERED_STYLES = {
            '1' => :decimal,
            'a' => :lower_alpha,
            'A' => :upper_alpha,
            'i' => :lower_roman,
            'I' => :upper_roman,
          }.freeze

          BULLETS = %w[• ◦ ▪].freeze
          BULLET_STYLES = { 'disc' => '•', 'circle' => '◦', 'square' => '▪' }.freeze

          ROMAN_NUMERALS = [
            [1000, 'M'], [900, 'CM'], [500, 'D'], [400, 'CD'],
            [100, 'C'], [90, 'XC'], [50, 'L'], [40, 'XL'],
            [10, 'X'], [9, 'IX'], [5, 'V'], [4, 'IV'], [1, 'I']
          ].freeze

          CSS_BULLETS = { disc: '•', circle: '◦', square: '▪', none: '' }.freeze
          CSS_ORDERED_STYLES = %i[decimal lower_alpha upper_alpha lower_roman upper_roman].freeze

          class << self
            def context_for(element, ordered:, depth:, css_style: nil)
              attrs = element.attributes
              return ordered_context(attrs, css_style) if ordered

              new(ordered: false, index: nil, style: bullet_for(attrs['type'], depth, css_style))
            end

            # <li value="N"> restarts ordered numbering at N.
            def apply_item_value(list_context, element)
              return unless list_context&.ordered

              value = element.attributes['value'].to_i
              list_context.index = value if value.positive?
            end

            private

            def ordered_context(attrs, css_style)
              start = attrs['start'].to_i
              new(
                ordered: true,
                index: start.positive? ? start : 1,
                style: ordered_style(attrs['type'], css_style)
              )
            end

            def ordered_style(type_attr, css_style)
              from_attr = ORDERED_STYLES[type_attr.to_s]
              return from_attr if from_attr
              return css_style if CSS_ORDERED_STYLES.include?(css_style)

              :decimal
            end

            def bullet_for(type, depth, css_style)
              from_attr = BULLET_STYLES[type.to_s.downcase]
              return from_attr if from_attr

              from_css = css_style && CSS_BULLETS[css_style]
              from_css || BULLETS[[depth, BULLETS.length - 1].min]
            end
          end

          attr_accessor :index
          attr_reader :ordered, :style

          def initialize(ordered:, index:, style:)
            @ordered = ordered
            @index = index
            @style = style
          end

          def marker
            return style.to_s unless ordered

            "#{format_ordinal(index.to_i)}."
          end

          def advance
            self.index += 1 if ordered
          end

          private

          def format_ordinal(number)
            case style
            when :lower_alpha then alpha_ordinal(number)
            when :upper_alpha then alpha_ordinal(number).upcase
            when :lower_roman then roman_ordinal(number).downcase
            when :upper_roman then roman_ordinal(number)
            else number.to_s
            end
          end

          def alpha_ordinal(number)
            return number.to_s if number < 1

            result = +''
            n = number
            while n.positive?
              n, remainder = (n - 1).divmod(26)
              result.prepend((97 + remainder).chr)
            end
            result
          end

          def roman_ordinal(number)
            return number.to_s if number < 1 || number > 3999

            ROMAN_NUMERALS.each_with_object(+'') do |(value, numeral), result|
              while number >= value
                result << numeral
                number -= value
              end
            end
          end
        end
      end
    end
  end
end
