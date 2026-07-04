# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Css
        # Parses CSS selectors into compound chains and matches them against
        # REXML elements. Supported: type/universal, .class, #id, attribute
        # selectors ([attr], [attr=v], [attr~=v], [attr|=v], including the
        # `ns|attr` namespace form used by epub:type selectors), :first-child /
        # :last-child, and descendant/child/adjacent-sibling combinators.
        # Selectors using anything else parse to nil and their rule is dropped
        # — the standard "invalid selector invalidates the rule" behavior.
        class SelectorMatcher
          Compound = Struct.new(:tag, :classes, :id, :attrs, :pseudos)
          Part = Struct.new(:combinator, :compound)

          SIMPLE_TOKEN = /\*|[A-Za-z][\w-]*|\.[\w.-]+|#[\w-]+|\[[^\]]*\]|::?[\w-]+(?:\([^)]*\))?/
          ATTR_PATTERN = /\A\[\s*([\w|:-]+)\s*(?:([~|^$*]?=)\s*(?:"([^"]*)"|'([^']*)'|([^\]\s]*)))?\s*\]\z/
          SUPPORTED_PSEUDOS = %w[first-child last-child].freeze

          class << self
            # @return [Array<Part>, nil] parsed chain, or nil when unsupported
            def parse(selector_text)
              tokens = tokenize(selector_text.to_s.strip)
              return nil if tokens.nil? || tokens.empty?

              build_parts(tokens)
            end

            def specificity(parts)
              parts.sum { |part| compound_specificity(part.compound) }
            end

            # @param element [REXML::Element]
            # @param parts [Array<Part>] parsed selector chain
            def match?(element, parts)
              match_from?(element, parts, parts.length - 1)
            end

            private

            def tokenize(text)
              tokens = []
              scanner = text.dup
              until scanner.empty?
                token, scanner = next_token(scanner, tokens)
                return nil if token == :invalid

                tokens << token if token
              end
              tokens
            end

            def next_token(scanner, tokens)
              if (combinator = scanner[/\A\s*([>+~])\s*/, 1])
                return [:invalid, ''] if combinator == '~'

                return [combinator == '>' ? :child : :adjacent, scanner.sub(/\A\s*[>+~]\s*/, '')]
              end
              return [:descendant, scanner.sub(/\A\s+/, '')] if scanner =~ /\A\s+/ && !tokens.empty?

              simple_token(scanner.sub(/\A\s+/, ''))
            end

            def simple_token(scanner)
              token = scanner[SIMPLE_TOKEN]
              return [:invalid, ''] unless token && scanner.start_with?(token)

              [token, scanner[token.length..]]
            end

            def build_parts(tokens)
              parts = [Part.new(combinator: nil, compound: empty_compound)]
              tokens.each do |token|
                next_part_result = apply_token?(parts, token)
                return nil unless next_part_result
              end
              return nil if parts.any? { |part| blank_compound?(part.compound) }

              parts
            end

            def apply_token?(parts, token)
              if %i[descendant child adjacent].include?(token)
                parts << Part.new(combinator: token, compound: empty_compound)
                return true
              end

              apply_simple?(parts.last.compound, token)
            end

            def apply_simple?(compound, token)
              case token[0]
              when '.' then token[1..].split('.').each { |name| compound.classes << name }
              when '#' then compound.id = token[1..]
              when '[' then return apply_attr?(compound, token)
              when ':' then return apply_pseudo?(compound, token)
              else compound.tag = token.downcase
              end
              true
            end

            def apply_attr?(compound, token)
              match = ATTR_PATTERN.match(token)
              return false unless match

              name = match[1].tr('|', ':').downcase
              value = match[3] || match[4] || match[5]
              compound.attrs << [name, match[2], value]
              true
            end

            def apply_pseudo?(compound, token)
              name = token.delete_prefix('::').delete_prefix(':')
              return false unless SUPPORTED_PSEUDOS.include?(name)

              compound.pseudos << name.tr('-', '_').to_sym
              true
            end

            def empty_compound
              Compound.new(tag: nil, classes: [], id: nil, attrs: [], pseudos: [])
            end

            def blank_compound?(compound)
              compound.tag.nil? && compound.classes.empty? && compound.id.nil? &&
                compound.attrs.empty? && compound.pseudos.empty?
            end

            def compound_specificity(compound)
              ids = compound.id ? 1 : 0
              classes = compound.classes.length + compound.attrs.length + compound.pseudos.length
              tags = compound.tag ? 1 : 0
              (ids * 10_000) + (classes * 100) + tags
            end

            def match_from?(element, parts, index)
              return false unless element.is_a?(REXML::Element)
              return false unless match_compound?(element, parts[index].compound)
              return true if index.zero?

              step_combinator?(element, parts, index)
            end

            def step_combinator?(element, parts, index)
              case parts[index].combinator
              when :child then match_from?(parent_element(element), parts, index - 1)
              when :adjacent then match_from?(element.previous_element, parts, index - 1)
              else match_ancestors?(element, parts, index - 1)
              end
            end

            def match_ancestors?(element, parts, index)
              ancestor = parent_element(element)
              while ancestor
                return true if match_from?(ancestor, parts, index)

                ancestor = parent_element(ancestor)
              end
              false
            end

            def parent_element(element)
              parent = element.parent
              parent.is_a?(REXML::Element) ? parent : nil
            end

            def match_compound?(element, compound)
              return false if compound.tag && compound.tag != '*' && element.name.downcase != compound.tag
              return false if compound.id && element.attributes['id'] != compound.id
              return false unless classes_match?(element, compound)
              return false unless attrs_match?(element, compound)

              pseudos_match?(element, compound)
            end

            def classes_match?(element, compound)
              return true if compound.classes.empty?

              element_classes = element.attributes['class'].to_s.split
              compound.classes.all? { |name| element_classes.include?(name) }
            end

            def attrs_match?(element, compound)
              compound.attrs.all? do |(name, operator, value)|
                attr_value = element.attributes[name]
                attr_matches?(attr_value, operator, value)
              end
            end

            def attr_matches?(attr_value, operator, value)
              return false if attr_value.nil?
              return true if operator.nil?

              case operator
              when '=' then attr_value == value
              when '~=' then attr_value.split.include?(value)
              when '|=' then attr_value == value || attr_value.start_with?("#{value}-")
              else attr_substring_matches?(attr_value, operator, value)
              end
            end

            def attr_substring_matches?(attr_value, operator, value)
              case operator
              when '^=' then attr_value.start_with?(value.to_s)
              when '$=' then attr_value.end_with?(value.to_s)
              when '*=' then attr_value.include?(value.to_s)
              else false
              end
            end

            def pseudos_match?(element, compound)
              compound.pseudos.all? do |pseudo|
                case pseudo
                when :first_child then element.previous_element.nil?
                when :last_child then element.next_element.nil?
                else false
                end
              end
            end
          end
        end
      end
    end
  end
end
