# frozen_string_literal: true

module Shoko
  module Core
    module BookFormats
      module Fb2
        # Canonical parser for FB2 title-info metadata fields.
        class MetadataParser
          class << self
            # @param doc [REXML::Document]
            # @return [Hash] canonical metadata hash
            def parse_document(doc)
              title_info = locate_title_info(doc)
              raise Shoko::MalformedMetadataInputError, 'FB2 metadata missing description/title-info' unless title_info

              {
                title: extract_text(title_info, 'book-title'),
                authors: extract_authors(title_info),
                year: extract_year(title_info),
                language: extract_text(title_info, 'lang'),
              }
            end

            private

            def locate_title_info(doc)
              find_element(doc, 'description/title-info') ||
                find_element(doc, 'FictionBook/description/title-info')
            end

            def find_element(context, path)
              parts = path.to_s.split('/')
              current = context.is_a?(REXML::Document) ? context.root : context
              return nil unless current

              parts.each do |part|
                current = current.elements.detect { |el| el.name.to_s.casecmp(part).zero? }
                return nil unless current
              end
              current
            end

            def extract_text(parent, tag)
              return nil unless parent

              element = parent.elements[tag]
              return nil unless element

              text = collect_text(element).strip
              text.empty? ? nil : text
            end

            def collect_text(element)
              text = +''
              element.each_child do |child|
                case child
                when REXML::Text then text << child.value
                when REXML::Element then text << collect_text(child)
                end
              end
              text
            end

            def extract_authors(title_info)
              authors = []
              title_info.elements.each('author') do |author_element|
                first = extract_text(author_element, 'first-name')
                middle = extract_text(author_element, 'middle-name')
                last = extract_text(author_element, 'last-name')
                nickname = extract_text(author_element, 'nickname')

                parts = [first, middle, last].compact
                name = parts.empty? ? nickname : parts.join(' ')
                authors << name if name && !name.empty?
              end
              authors
            end

            def extract_year(title_info)
              date_element = title_info.elements['date']
              return nil unless date_element

              raw = date_element.attributes['value'] || collect_text(date_element)
              return nil unless raw

              match = raw.match(/\d{4}/)
              match && match[0]
            end
          end
        end
      end
    end
  end
end
