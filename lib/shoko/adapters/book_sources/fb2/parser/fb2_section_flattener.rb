# frozen_string_literal: true

require_relative 'element_text'
require 'rexml/document'

module Shoko
  module Adapters
    module BookSources
      module Fb2
        # Flattens recursive FB2 <section> elements into a linear array of
        # chapter-like entries, each with a title and XML fragment.
        #
        # FB2 sections can nest arbitrarily deep.  This class walks the tree and
        # produces one entry per leaf section (or per section that has direct
        # content besides child sections).
        module Fb2SectionFlattener
          FlatSection = Struct.new(:title, :element, :depth)
          XLINK_NAMESPACE = 'http://www.w3.org/1999/xlink'

          module_function

          # @param body_element [REXML::Element] the <body> element
          # @return [Array<FlatSection>]
          def flatten(body_element)
            return [] unless body_element

            sections = []
            body_element.elements.each do |child|
              next unless child.name.to_s.downcase == 'section'

              flatten_section(child, 0, sections)
            end

            # If no sections found, treat the entire body as one chapter
            sections << FlatSection.new(title: nil, element: body_element, depth: 0) if sections.empty?

            sections
          end

          def flatten_section(section, depth, acc)
            child_sections = section.elements.select { |element| element.name.to_s.downcase == 'section' }
            return append_leaf_section(section, depth, acc) if child_sections.empty?

            append_preamble_section(section, child_sections.first, depth, acc)
            child_sections.each { |child| flatten_section(child, depth + 1, acc) }
          end
          private_class_method :flatten_section

          def append_leaf_section(section, depth, acc)
            acc << FlatSection.new(title: extract_section_title(section), element: section, depth: depth)
          end
          private_class_method :append_leaf_section

          def append_preamble_section(section, first_child_section, depth, acc)
            return unless preamble_content?(section, first_child_section)

            acc << FlatSection.new(
              title: extract_section_title(section),
              element: build_preamble_element(section, first_child_section),
              depth: depth
            )
          end
          private_class_method :append_preamble_section

          # Build a synthetic <section> XML string containing only the content
          # before the first child section (title, epigraph, etc.)
          def build_preamble_element(section, first_child_section)
            xml = %(<section xmlns:l="#{XLINK_NAMESPACE}">)
            formatter = REXML::Formatters::Default.new
            section.each_child do |child|
              break if child.equal?(first_child_section)

              buf = +''
              formatter.write(child, buf)
              xml << buf
            end
            xml << '</section>'
            REXML::Document.new(xml).root
          rescue REXML::ParseException, REXML::UndefinedNamespaceException
            # Fallback: empty section
            REXML::Element.new('section')
          end
          private_class_method :build_preamble_element

          def extract_section_title(section)
            title_el = section.elements.detect { |el| el.name.to_s.downcase == 'title' }
            return nil unless title_el

            # Collect all <p> text from within <title>
            paragraphs = []
            title_el.elements.each do |el|
              next unless el.name.to_s.downcase == 'p'

              paragraphs << element_text(el)
            end

            result = paragraphs.join(' ').strip
            result.empty? ? element_text(title_el).strip : result
          end
          private_class_method :extract_section_title

          def element_text(element)
            ElementText.collect(element).gsub(/\s+/, ' ').strip
          end

          private_class_method :element_text

          # Check if a section has meaningful content elements before the first child section
          def preamble_content?(section, first_child_section)
            section.each_child do |child|
              return false if child.equal?(first_child_section)

              if child.is_a?(REXML::Element)
                name = child.name.to_s.downcase
                return true if %w[p image poem cite epigraph subtitle table].include?(name)
              end
            end
            false
          end
          private_class_method :preamble_content?
        end
      end
    end
  end
end
