# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Fb2
        class Fb2Importer
          # Handles XML loading, namespace normalization, and metadata extraction for FB2 sources.
          module XmlSupport
            private

            def read_fb2_xml(path)
              return read_from_zip(path) if path.downcase.end_with?('.fb2.zip')

              normalize_encoding(File.read(path))
            end

            def read_from_zip(path)
              @archive_reader.open(path, runtime_config: @runtime_config) do |zip|
                entry = zip.entries.find { |candidate| candidate.name.downcase.end_with?('.fb2') }
                raise Shoko::BookParseError.new('No .fb2 file found inside archive', path) unless entry

                normalize_encoding(zip.read(entry.name))
              end
            end

            def normalize_encoding(content)
              return content if content.nil?

              content.force_encoding('UTF-8')
              return content if content.valid_encoding?

              xml_encoding = content.match(/encoding=["']([^"']+)["']/i)&.captures&.first
              return content.encode('UTF-8', xml_encoding) if xml_encoding

              content.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
            end

            def parse_xml(xml)
              stripped = xml.gsub(/\s+xmlns\s*=\s*["'][^"']*["']/, '')
              REXML::Document.new(stripped)
            end

            def extract_metadata(doc)
              canonical = Adapters::BookSources::Fb2::MetadataParser.parse_document(doc)
              {
                title: canonical[:title],
                authors: canonical[:authors],
                language: canonical[:language],
                year: canonical[:year],
                genre: genre_for(doc),
              }.compact
            end

            def genre_for(doc)
              title_info = find_element(doc, 'description/title-info') ||
                           find_element(doc, 'FictionBook/description/title-info')
              element_text(title_info, 'genre')
            end

            def find_element(context, path)
              current = context.is_a?(REXML::Document) ? context.root : context
              return nil unless current

              path.split('/').each do |part|
                current = current.elements.detect { |element| element.name.to_s.casecmp?(part) }
                return nil unless current
              end
              current
            end

            def element_text(parent, tag)
              element = parent.elements[tag]
              return nil unless element

              text = collect_text(element).strip
              text.empty? ? nil : text
            end

            def collect_text(element)
              text = +''
              element.each_child do |child|
                case child
                when REXML::Text
                  text << child.value
                when REXML::Element
                  text << collect_text(child)
                end
              end
              text
            end
          end
        end
      end
    end
  end
end
