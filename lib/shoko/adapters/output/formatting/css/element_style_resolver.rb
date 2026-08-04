# frozen_string_literal: true

require_relative 'stylesheet_parser'
require_relative 'selector_matcher'

module Shoko
  module Adapters
    module Output
      module Formatting
        module Css
          # Resolves the computed style of REXML elements against a compiled rule
          # list: cascade (specificity + source order + !important), inheritance
          # for inheritable properties, and font-size ratio composition. Results
          # are memoized twice — per element, and per structural signature so
          # runs of identically-positioned elements (every plain <p> in a
          # chapter) are matched against the rules only once.
          class ElementStyleResolver
            INHERITED_KEYS = %i[
              italic bold small_caps underline strikethrough fg align transform
              tracking list_style code text_indent preserve_whitespace no_break
            ].freeze

            # Columns per em: a terminal cell is roughly half an em wide.
            EM_TO_COLS = 2.0
            SMALL_RATIO = 0.84
            LARGE_RATIO = 1.15

            def initialize(rules:)
              @rules = Array(rules)
              @computed_by_element = {}.compare_by_identity
              @computed_by_key = {}
              @key_by_element = {}.compare_by_identity
              @key_ids = Hash.new { |hash, key| hash[key] = hash.length + 1 }
              @inline_by_element = {}.compare_by_identity
              @block_by_element = {}.compare_by_identity
            end

            def any_rules?
              !@rules.empty?
            end

            def computed_style(element)
              @computed_by_element[element] ||= begin
                key = structural_key(element)
                @computed_by_key[key] ||= build_computed(element)
              end
            end

            def display(element)
              computed_style(element)[:display]
            end

            def display_none?(element)
              display(element) == :none
            end

            def block_display?(element)
              %i[block list_item].include?(display(element))
            end

            # Inline segment styles derived from the element's computed style.
            def inline_styles(element)
              @inline_by_element[element] ||= build_inline_styles(computed_style(element))
            end

            # Block-level typography metadata derived from the computed style.
            def block_metadata(element)
              @block_by_element[element] ||= build_block_metadata(computed_style(element))
            end

            def list_style(element)
              computed_style(element)[:list_style]
            end

            private

            def structural_key(element)
              @key_by_element[element] ||= build_structural_key(element)
            end

            # The key must capture everything the supported selectors can see:
            # ancestors (via the parent's key id), up to three previous siblings
            # (adjacent-combinator chains), and — because :last-child is the one
            # supported pseudo that looks forward — whether the element is the
            # last child. Without that bit, the last element of a run of
            # identically-shaped siblings would inherit the memoized style of a
            # middle sibling and :last-child rules would never (or wrongly) apply.
            def build_structural_key(element)
              parent = element.parent
              parent_id = parent.is_a?(REXML::Element) ? @key_ids[structural_key(parent)] : 0
              prev1 = element.previous_element
              prev2 = prev1&.previous_element
              prev3 = prev2&.previous_element
              [parent_id, shallow_signature(element), element.next_element.nil?,
               shallow_signature(prev1), shallow_signature(prev2), shallow_signature(prev3)]
            end

            def shallow_signature(element)
              return nil unless element

              attrs = element.attributes
              [element.name.downcase, attrs['class'].to_s, attrs['id'].to_s, attrs['epub:type'].to_s]
            end

            def build_computed(element)
              inherited = inherited_style(element)
              own = cascaded_declarations(element)
              compose_computed(inherited, own)
            end

            def inherited_style(element)
              parent = element.parent
              return {} unless parent.is_a?(REXML::Element)

              parent_computed = computed_style(parent)
              inherited = parent_computed.slice(*INHERITED_KEYS)
              font_size = parent_computed[:font_size]
              inherited[:font_size] = font_size if font_size
              inherited
            end

            def cascaded_declarations(element)
              matched = @rules.select { |rule| SelectorMatcher.match?(element, rule.selector) }
              return {} if matched.empty?

              fold_declarations(matched)
            end

            def fold_declarations(matched)
              normal = {}
              important = {}
              matched.sort_by { |rule| [rule.specificity, rule.order] }.each do |rule|
                rule.declarations.each do |(key, value, flagged)|
                  (flagged ? important : normal)[key] = value
                end
              end
              normal.merge(important)
            end

            def compose_computed(inherited, own)
              computed = inherited.merge(own.except(:font_size))
              font_size = composed_font_size(inherited[:font_size], own[:font_size])
              computed[:font_size] = font_size if font_size
              computed
            end

            def composed_font_size(inherited_ratio, own_spec)
              return inherited_ratio unless own_spec
              return own_spec[:absolute] if own_spec[:absolute]

              (inherited_ratio || 1.0) * own_spec[:relative].to_f
            end

            def build_inline_styles(computed)
              styles = {}
              apply_boolean_styles(styles, computed)
              apply_color_styles(styles, computed)
              apply_size_styles(styles, computed)
              styles[:transform] = computed[:transform] if computed[:transform]
              styles.freeze
            end

            def apply_boolean_styles(styles, computed)
              %i[italic bold small_caps underline strikethrough superscript subscript
                 code preserve_whitespace no_break].each do |key|
                styles[key] = computed[key] if computed.key?(key)
              end
            end

            def apply_color_styles(styles, computed)
              styles[:fg] = computed[:fg] if computed[:fg]
              styles[:bg] = computed[:bg] if computed[:bg]
            end

            def apply_size_styles(styles, computed)
              ratio = computed[:font_size]
              return unless ratio

              styles[:small] = true if ratio <= SMALL_RATIO
              styles[:large] = true if ratio >= LARGE_RATIO
            end

            def build_block_metadata(computed)
              metadata = {}
              apply_alignment_metadata(metadata, computed)
              apply_indent_metadata(metadata, computed)
              apply_spacing_metadata(metadata, computed)
              metadata[:boxed] = true if computed[:boxed]
              metadata[:bg] = computed[:bg] if computed[:bg]
              metadata.freeze
            end

            def apply_alignment_metadata(metadata, computed)
              align = computed[:align]
              metadata[:align] = align if align
            end

            def apply_indent_metadata(metadata, computed)
              apply_text_indent_metadata(metadata, computed[:text_indent])
              left = computed[:margin_left].to_f + computed[:padding_left].to_f
              right = computed[:margin_right].to_f + computed[:padding_right].to_f
              metadata[:indent_left] = em_to_cols(left) if left.positive?
              metadata[:indent_right] = em_to_cols(right) if right.positive?
            end

            def apply_text_indent_metadata(metadata, indent)
              metadata[:first_line_indent] = em_to_cols(indent) if indent&.positive?
              metadata[:hanging_indent] = em_to_cols(-indent) if indent&.negative?
            end

            def apply_spacing_metadata(metadata, computed)
              metadata[:spacing_before] = spacing_bucket(computed[:margin_top]) if computed.key?(:margin_top)
              metadata[:spacing_after] = spacing_bucket(computed[:margin_bottom]) if computed.key?(:margin_bottom)
            end

            def spacing_bucket(ems)
              value = ems.to_f
              return 0 if value < 0.3
              return 1 if value < 1.9

              2
            end

            def em_to_cols(ems)
              cols = (ems.to_f * EM_TO_COLS).round
              cols.clamp(0, 24)
            end
          end
        end
      end
    end
  end
end
