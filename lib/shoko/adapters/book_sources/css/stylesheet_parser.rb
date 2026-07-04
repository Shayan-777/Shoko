# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Css
        # Parses stylesheet text into an ordered list of rules whose
        # declarations are pre-normalized into Shoko's terminal style
        # vocabulary. Only properties with a terminal representation are kept
        # (the whitelist below); everything else — fonts as files, positioning,
        # floats — is dropped at parse time. Malformed constructs are skipped,
        # never raised.
        class StylesheetParser
          # One parsed rule: selector chain (see SelectorMatcher), normalized
          # declarations ([key, value, important] triples), specificity, and
          # source order.
          Rule = Struct.new(:selector, :declarations, :specificity, :order)

          COMMENT_PATTERN = %r{/\*.*?\*/}m
          MEDIA_CONDITION = /\A@media\s+([^{]*)\z/i
          SUPPORTED_MEDIA = /\b(?:all|screen)\b/i

          ALIGN_VALUES = {
            'left' => :left, 'start' => :left, 'right' => :right, 'end' => :right,
            'center' => :center, 'justify' => :justify
          }.freeze

          FONT_SIZE_NAMES = {
            'xx-small' => 0.58, 'x-small' => 0.69, 'small' => 0.83, 'medium' => 1.0,
            'large' => 1.17, 'x-large' => 1.5, 'xx-large' => 2.0
          }.freeze

          LIST_STYLE_TYPES = {
            'disc' => :disc, 'circle' => :circle, 'square' => :square,
            'decimal' => :decimal, 'lower-alpha' => :lower_alpha, 'lower-latin' => :lower_alpha,
            'upper-alpha' => :upper_alpha, 'upper-latin' => :upper_alpha,
            'lower-roman' => :lower_roman, 'upper-roman' => :upper_roman, 'none' => :none
          }.freeze

          MONO_FAMILY_PATTERN = /mono|courier|consolas|menlo/i
          LENGTH_PATTERN = /(-?[\d.]+)\s*(em|rem|%|px|pt)?/

          def self.parse(text)
            new(text).parse
          end

          def initialize(text)
            @text = text.to_s.gsub(COMMENT_PATTERN, ' ')
            @rules = []
          end

          # @return [Array<Rule>]
          def parse
            consume_block(@text)
            @rules
          end

          private

          def consume_block(text)
            scanner_position = 0
            while (opening = text.index('{', scanner_position))
              preamble = text[scanner_position...opening].strip
              closing = matching_close(text, opening)
              break unless closing

              handle_segment(preamble, text[(opening + 1)...closing])
              scanner_position = closing + 1
            end
          end

          def matching_close(text, opening)
            depth = 0
            (opening...text.length).each do |index|
              depth += 1 if text[index] == '{'
              depth -= 1 if text[index] == '}'
              return index if depth.zero?
            end
            nil
          end

          def handle_segment(preamble, body)
            preamble = strip_statement_at_rules(preamble)
            return if preamble.empty?

            if (media = MEDIA_CONDITION.match(preamble))
              consume_block(body) if SUPPORTED_MEDIA.match?(media[1])
            elsif preamble.start_with?('@')
              nil # unsupported at-rule with a block: skip it entirely
            else
              append_rules(preamble, body)
            end
          end

          # @import/@charset/@namespace statements can precede a selector in the
          # same scanned preamble; they carry no block, so drop them.
          def strip_statement_at_rules(preamble)
            preamble.gsub(/@(?:import|charset|namespace)[^;]*;/i, ' ').strip
          end

          def append_rules(selector_group, body)
            declarations = parse_declarations(body)
            return if declarations.empty?

            selector_group.split(',').each do |selector_text|
              selector = SelectorMatcher.parse(selector_text)
              next unless selector

              @rules << Rule.new(
                selector: selector,
                declarations: declarations,
                specificity: SelectorMatcher.specificity(selector),
                order: @rules.length
              )
            end
          end

          def parse_declarations(body)
            body.split(';').flat_map do |declaration|
              property, _, raw_value = declaration.partition(':')
              next [] if raw_value.empty?

              value = raw_value.strip
              important = value.sub!(/\s*!important\z/i, '') ? true : false
              normalize_declaration(property.strip.downcase, value.strip, important)
            end
          end

          def normalize_declaration(property, value, important)
            pairs = normalized_pairs(property, value)
            Array(pairs).filter_map do |key, normalized|
              next if normalized.nil? && !nullable_key?(key)

              [key, normalized, important]
            end
          end

          def nullable_key?(key)
            key == :transform
          end

          def normalized_pairs(property, value)
            font_pairs(property, value) ||
              text_pairs(property, value) ||
              box_pairs(property, value) ||
              color_pairs(property, value) ||
              misc_pairs(property, value)
          end

          def font_pairs(property, value)
            case property
            when 'font-style' then [[:italic, /italic|oblique/i.match?(value)]]
            when 'font-weight' then weight_pairs(value)
            when 'font-variant', 'font-variant-caps' then variant_pairs(value)
            when 'font-size' then [[:font_size, font_size_value(value)]]
            when 'font-family' then [[:code, MONO_FAMILY_PATTERN.match?(value)]]
            when 'font' then font_shorthand_pairs(value)
            end
          end

          def text_pairs(property, value)
            case property
            when 'text-align' then align_pairs(value)
            when 'text-indent' then indent_pairs(value)
            when 'text-transform' then [[:transform, value.casecmp('uppercase').zero? ? :upcase : nil]]
            when 'text-decoration', 'text-decoration-line' then decoration_pairs(value)
            else text_extra_pairs(property, value)
            end
          end

          def text_extra_pairs(property, value)
            case property
            when 'vertical-align' then vertical_pairs(value)
            when 'letter-spacing' then [[:tracking, positive_tracking?(value)]]
            when 'white-space' then white_space_pairs(value)
            end
          end

          def box_pairs(property, value)
            margin_pairs(property, value) || padding_pairs(property, value) || border_pairs(property, value)
          end

          def margin_pairs(property, value)
            case property
            when 'margin' then margin_shorthand_pairs(value)
            when 'margin-top' then [[:margin_top, length_in_em(value)]]
            when 'margin-bottom' then [[:margin_bottom, length_in_em(value)]]
            when 'margin-left' then [[:margin_left, length_in_em(value)]]
            when 'margin-right' then [[:margin_right, length_in_em(value)]]
            end
          end

          def padding_pairs(property, value)
            case property
            when 'padding' then padding_shorthand_pairs(value)
            when 'padding-left' then [[:padding_left, length_in_em(value)]]
            when 'padding-right' then [[:padding_right, length_in_em(value)]]
            end
          end

          def border_pairs(property, value)
            return nil unless /\Aborder(?:-(?:top|bottom|left|right))?\z/.match?(property)

            [[:boxed, bordered_value?(value)]]
          end

          def color_pairs(property, value)
            case property
            when 'color' then [[:fg, color_value(value)]]
            when 'background', 'background-color' then [[:bg, color_value(value)]]
            end
          end

          def misc_pairs(property, value)
            case property
            when 'display' then [[:display, display_value(value)]]
            when 'list-style-type' then [[:list_style, LIST_STYLE_TYPES[value.downcase]]]
            when 'list-style' then list_style_shorthand_pairs(value)
            end
          end

          def weight_pairs(value)
            case value.downcase
            when 'bold', 'bolder', /\A[6-9]00\z/ then [[:bold, true]]
            when 'normal', 'lighter', /\A[1-5]00\z/ then [[:bold, false]]
            end
          end

          def variant_pairs(value)
            return [[:small_caps, true]] if /small-caps/i.match?(value)
            return [[:small_caps, false]] if value.casecmp('normal').zero?

            nil
          end

          def align_pairs(value)
            cleaned = value.downcase.strip
            return nil if cleaned == 'inherit'

            align = ALIGN_VALUES[cleaned]
            align ? [[:align, align]] : nil
          end

          def indent_pairs(value)
            em = length_in_em(value)
            em ? [[:text_indent, em]] : nil
          end

          def decoration_pairs(value)
            return [[:underline, false], [:strikethrough, false]] if value.casecmp('none').zero?

            pairs = []
            pairs << [:underline, true] if /underline/i.match?(value)
            pairs << [:strikethrough, true] if /line-through/i.match?(value)
            pairs.empty? ? nil : pairs
          end

          def vertical_pairs(value)
            case value.downcase
            when /super/ then [[:superscript, true]]
            when /sub/ then [[:subscript, true]]
            when 'baseline' then [[:superscript, false], [:subscript, false]]
            end
          end

          def white_space_pairs(value)
            case value.downcase
            when /\Apre/ then [[:preserve_whitespace, true]]
            when 'nowrap' then [[:no_break, true]]
            when 'normal' then [[:preserve_whitespace, false], [:no_break, false]]
            end
          end

          def margin_shorthand_pairs(value)
            top, right, bottom, left = expand_box_shorthand(value)
            [
              [:margin_top, top], [:margin_right, right],
              [:margin_bottom, bottom], [:margin_left, left]
            ].reject { |(_, em)| em.nil? }
          end

          def padding_shorthand_pairs(value)
            _top, right, _bottom, left = expand_box_shorthand(value)
            [[:padding_right, right], [:padding_left, left]].reject { |(_, em)| em.nil? }
          end

          def expand_box_shorthand(value)
            parts = value.split(/\s+/).map { |part| length_in_em(part) }
            case parts.length
            when 1 then [parts[0]] * 4
            when 2 then [parts[0], parts[1], parts[0], parts[1]]
            when 3 then [parts[0], parts[1], parts[2], parts[1]]
            when 4 then parts
            else [nil, nil, nil, nil]
            end
          end

          def list_style_shorthand_pairs(value)
            value.split(/\s+/).each do |token|
              style = LIST_STYLE_TYPES[token.downcase]
              return [[:list_style, style]] if style
            end
            nil
          end

          # font shorthand: only mine style/weight/family signals out of it.
          def font_shorthand_pairs(value)
            pairs = []
            pairs << [:italic, true] if /\b(?:italic|oblique)\b/i.match?(value)
            pairs << [:bold, true] if /\b(?:bold|[6-9]00)\b/.match?(value)
            pairs << [:code, true] if MONO_FAMILY_PATTERN.match?(value)
            pairs.empty? ? nil : pairs
          end

          def font_size_value(value)
            named = FONT_SIZE_NAMES[value.downcase]
            return { absolute: named } if named
            return { relative: 0.83 } if value.casecmp('smaller').zero?
            return { relative: 1.2 } if value.casecmp('larger').zero?

            scaled_font_size(value)
          end

          def scaled_font_size(value)
            match = LENGTH_PATTERN.match(value)
            return nil unless match

            number = match[1].to_f
            case match[2]
            when 'em', 'rem' then { relative: number }
            when '%' then { relative: number / 100.0 }
            when 'px' then { absolute: number / 16.0 }
            when 'pt' then { absolute: number / 12.0 }
            end
          end

          def length_in_em(value)
            text = value.to_s
            return 0.0 if text.strip == '0' || text.casecmp('auto').zero?

            match = LENGTH_PATTERN.match(text)
            match ? scale_length(match[1].to_f, match[2]) : nil
          end

          def scale_length(number, unit)
            case unit
            when 'em', 'rem', nil then number
            when '%' then number / 100.0
            when 'px' then number / 16.0
            when 'pt' then number / 12.0
            end
          end

          def positive_tracking?(value)
            return false if value.casecmp('normal').zero?

            ems = length_in_em(value)
            !ems.nil? && ems.positive?
          end

          def bordered_value?(value)
            cleaned = value.downcase.strip
            !cleaned.empty? && cleaned != 'none' && cleaned != '0'
          end

          def display_value(value)
            case value.downcase
            when 'none' then :none
            when 'block', 'flex', 'grid' then :block
            when 'list-item' then :list_item
            else :inline
            end
          end

          def color_value(value)
            token = value[/#\h{3,8}|rgba?\([^)]*\)|[a-z]+/i]
            return nil if token.nil?
            return nil if %w[inherit initial unset transparent currentcolor none url].include?(token.downcase)

            token
          end
        end
      end
    end
  end
end

require_relative 'selector_matcher'
