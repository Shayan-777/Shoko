# frozen_string_literal: true

require_relative '../../../../core/models/content_block'

module Shoko
  module Adapters
    module BookSources
      module Fb2
        # Extracts inline text and styling from FB2 XML elements, producing
        # an array of {Core::Models::TextSegment} objects.
        module Fb2InlineParser
          module_function

          STYLE_ELEMENTS = {
            'strong' => { bold: true },
            'emphasis' => { italic: true },
            'strikethrough' => { strikethrough: true },
            'code' => { code: true },
            'sup' => { superscript: true },
            'sub' => { subscript: true },
          }.freeze

          # Build an array of TextSegment from the children of +element+.
          #
          # @param element [REXML::Element]
          # @param inherited_styles [Hash] styles inherited from parent
          # @return [Array<Core::Models::TextSegment>]
          def build_segments(element, inherited_styles = {})
            segments = []
            collect_segments(element, inherited_styles, segments)
            merge_adjacent_segments(segments)
          end

          # Extract plain text from an element tree, stripping all markup.
          #
          # @param element [REXML::Element]
          # @return [String]
          def plain_text(element)
            return '' unless element

            collect_all_text(element).gsub(/\s+/, ' ').strip
          end

          def collect_all_text(element)
            text = +''
            element.each_child do |child|
              case child
              when REXML::Text then text << child.value
              when REXML::Element then text << collect_all_text(child)
              end
            end
            text
          end

          private_class_method :collect_all_text

          def collect_segments(element, styles, segments)
            return unless element

            element.each_child do |child|
              case child
              when REXML::Text
                text = normalize_text(child.value)
                segments << Core::Models::TextSegment.new(text: text, styles: styles.dup) unless text.empty?
              when REXML::Element
                process_inline_element(child, styles, segments)
              end
            end
          end
          private_class_method :collect_segments

          def process_inline_element(element, parent_styles, segments)
            local_name = element.name.to_s.downcase

            case local_name
            when *STYLE_ELEMENTS.keys
              merged = parent_styles.merge(STYLE_ELEMENTS[local_name])
              collect_segments(element, merged, segments)
            when 'a'
              href = element.attributes['href'] || element.attributes['l:href'] || ''
              merged = parent_styles.merge(link: href)
              collect_segments(element, merged, segments)
            when 'br'
              segments << Core::Models::TextSegment.new(text: "\n", styles: parent_styles.merge(break: true))
            when 'image'
              # inline image reference — skip, handled at block level
            else
              collect_segments(element, parent_styles, segments)
            end
          end
          private_class_method :process_inline_element

          def normalize_text(text)
            text.to_s.gsub(/\s+/, ' ')
          end
          private_class_method :normalize_text

          def merge_adjacent_segments(segments)
            return segments if segments.size <= 1

            merged = [segments.first]
            segments[1..].each do |seg|
              prev = merged.last
              if prev.styles == seg.styles
                merged[-1] = Core::Models::TextSegment.new(text: prev.text + seg.text, styles: prev.styles)
              else
                merged << seg
              end
            end
            merged
          end
          private_class_method :merge_adjacent_segments
        end
      end
    end
  end
end
