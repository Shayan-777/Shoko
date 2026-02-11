# frozen_string_literal: true

require 'rexml/document'

module Shoko
  module Core::BookFormats::Fb2
    # Lightweight extractor for FB2 metadata (title, authors, year, language).
    # Opens the file and reads just the <description> block without loading
    # chapter content.
    class Fb2MetadataExtractor
      class << self
        # @param path [String] path to .fb2 or .fb2.zip file
        # @param text_reader [#call, nil] UTF-8 text file reader dependency
        # @param zip_entry_reader [#call, nil] reader for archive entry suffix
        # @return [Hash] normalized metadata
        def from_file(path, text_reader: nil, zip_entry_reader: nil, **_)
          xml = read_fb2(path, text_reader: text_reader, zip_entry_reader: zip_entry_reader)
          return {} unless xml

          stripped = xml.gsub(/\s+xmlns\s*=\s*["'][^"']*["']/, '')
          doc = REXML::Document.new(stripped)
          title_info = find_title_info(doc)
          return {} unless title_info

          normalize(extract_from_title_info(title_info))
        rescue StandardError
          {}
        end

        private

        def read_fb2(path, text_reader:, zip_entry_reader:)
          lower = path.to_s.downcase
          if lower.end_with?('.fb2.zip')
            return nil unless zip_entry_reader

            zip_entry_reader.call(path, '.fb2')
          else
            return nil unless text_reader

            text_reader.call(path)
          end
        rescue StandardError
          nil
        end

        def find_title_info(doc)
          root = doc.root
          return nil unless root

          desc = root.elements.detect { |el| el.name.to_s.downcase == 'description' }
          return nil unless desc

          desc.elements.detect { |el| el.name.to_s.downcase == 'title-info' }
        end

        def extract_from_title_info(ti)
          {
            title: extract_text(ti, 'book-title'),
            authors: extract_authors(ti),
            language: extract_text(ti, 'lang'),
            year: extract_date(ti),
          }
        end

        def extract_text(parent, tag)
          el = parent.elements[tag]
          return nil unless el

          result = collect_text(el).strip
          result.empty? ? nil : result
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

        def extract_authors(ti)
          authors = []
          ti.elements.each('author') do |author_el|
            first = extract_text(author_el, 'first-name')
            middle = extract_text(author_el, 'middle-name')
            last = extract_text(author_el, 'last-name')
            nickname = extract_text(author_el, 'nickname')

            parts = [first, middle, last].compact
            name = parts.empty? ? nickname : parts.join(' ')
            authors << name if name && !name.empty?
          end
          authors
        end

        def extract_date(ti)
          date_el = ti.elements['date']
          return nil unless date_el

          # Try value attribute first, then text content
          value = date_el.attributes['value']
          text = extract_text(ti, 'date')
          raw = value || text
          return nil unless raw

          # Extract first 4-digit year
          match = raw.match(/\d{4}/)
          match ? match[0] : nil
        end

        def normalize(meta)
          return {} unless meta.is_a?(Hash)

          authors = Array(meta[:authors]).compact.map(&:to_s).reject(&:empty?)
          {
            authors: authors,
            author_str: authors.join('; '),
            year: (meta[:year] || '').to_s[0, 4],
            title: meta[:title],
            language: meta[:language],
          }
        end
      end
    end
  end
end
