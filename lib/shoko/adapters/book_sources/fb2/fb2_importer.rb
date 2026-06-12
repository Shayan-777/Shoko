# frozen_string_literal: true

require 'base64'
require 'rexml/document'
require 'shoko/shared/errors'
require_relative '../archive/zip_reader'
require 'shoko/core/models/chapter'
require 'shoko/core/models/toc_entry'
require 'shoko/core/models/book_data'
require 'shoko/shared/text_sanitizer'
require 'shoko/adapters/book_sources/fb2/parser/fb2_section_flattener'
require 'shoko/adapters/book_sources/fb2/parser/fb2_metadata_extractor'
require 'shoko/adapters/book_sources/fb2/parser/metadata_parser'
require 'shoko/adapters/book_sources/fb2/parser/fb2_inline_parser'
require 'shoko/adapters/book_sources/format_registry'
require_relative '../../support/lifecycle_helpers'

module Shoko
  module Adapters
    module BookSources
      module Fb2
        # Imports an FB2 (FictionBook 2) file into the common BookData representation.
        # Handles both plain `.fb2` and zipped `.fb2.zip` sources.
        class Fb2Importer
          include Shoko::Adapters::Support::LifecycleHelpers

          DEFAULT_LANGUAGE = 'en_US'

          def initialize(formatting_service: nil, extract_resources: false,
                         progress_reporter: nil, instrumentation: nil,
                         runtime_config: nil,
                         archive_reader: Shoko::Adapters::BookSources::Archive::ZipReader)
            @formatting_service = formatting_service
            @extract_resources = extract_resources ? true : false
            @progress_reporter = progress_reporter
            @instrumentation = instrumentation
            @runtime_config = runtime_config
            @archive_reader = archive_reader
          end

          # @param path [String] path to .fb2 or .fb2.zip file
          # @return [Core::Models::BookData]
          def import(path)
            @fb2_path = validated_fb2_path(path)
            doc = parsed_fb2_document
            metadata = instrumented_fb2_metadata(doc)
            chapters = instrumented_fb2_chapters(doc)
            resources = instrumented_fb2_resources(doc)
            build_book_data(metadata, chapters, resources)
          rescue REXML::ParseException => e
            raise Shoko::BookParseError.new(e.message, path)
          rescue Shoko::Error => e
            raise if e.is_a?(Shoko::FileNotFoundError)

            raise Shoko::BookParseError.new(e.message, path)
          end

          private

          def validated_fb2_path(path)
            expanded = File.expand_path(path)
            raise Shoko::FileNotFoundError, path unless File.file?(expanded)

            expanded
          end

          def parsed_fb2_document
            report('Reading FB2 file...', progress: 0.0)
            xml = read_fb2_xml(@fb2_path)
            raise Shoko::BookParseError.new('Unable to read FB2 content', @fb2_path) unless xml

            report('Parsing FB2 document...', progress: 0.1)
            instrument('fb2.parse') { parse_xml(xml) }
          end

          def instrumented_fb2_metadata(doc)
            report('Extracting metadata...', progress: 0.2)
            instrument('fb2.metadata') { extract_metadata(doc) }
          end

          def instrumented_fb2_chapters(doc)
            report('Building chapters...', progress: 0.3)
            instrument('fb2.chapters') { build_chapters(doc) }
          end

          def instrumented_fb2_resources(doc)
            return {} unless @extract_resources

            report('Extracting resources...', progress: 0.8)
            instrument('fb2.resources') { extract_binary_resources(doc) }
          end

          def fallback_title(path)
            fallback_title_from_path(path, strip_suffixes: ['.fb2.zip']) { |text| sanitize(text) }
          end

          def detect_source_type(path)
            path.downcase.end_with?('.fb2.zip') ? :fb2_zip : :fb2
          end

          def ratio(done, total)
            denom = [total.to_f, 1.0].max
            done.to_f / denom
          end

          # XML loading, namespace normalization, and metadata extraction for FB2 sources.
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

          def build_book_data(metadata, chapters, resources)
            report('Building table of contents...', progress: 0.7)
            toc_entries = build_toc_entries(chapters)
            report('Finalizing...', progress: 0.9)
            Core::Models::BookData.new(**book_data_attributes(metadata, chapters, toc_entries, resources))
          end

          def book_data_attributes(metadata, chapters, toc_entries, resources)
            {
              title: metadata[:title] || fallback_title(@fb2_path),
              language: metadata[:language] || DEFAULT_LANGUAGE,
              authors: Array(metadata[:authors]).map(&:to_s),
              chapters: chapters,
              toc_entries: toc_entries,
              resources: resources,
              metadata: metadata,
              format_data: { format: :fb2, source_type: detect_source_type(@fb2_path) },
            }
          end

          def build_chapters(doc)
            bodies = collect_bodies(doc)
            return [error_chapter('No content found')] if bodies.empty?

            chapters = []
            Array(bodies).each_with_index { |body, body_index| append_body_chapters(chapters, body, body_index) }
            chapters.empty? ? [error_chapter('No chapters found')] : chapters
          end

          def append_body_chapters(chapters, body, body_index)
            context = body_chapter_context(body)
            Array(context[:sections]).each_with_index do |section, index|
              report_body_progress(index + 1, context[:total], chapters.length + 1)
              chapters << build_chapter_from_section(section, chapters.length + 1, body_index, context[:notes])
            end
          end

          def body_chapter_context(body)
            sections = Adapters::BookSources::Fb2::Fb2SectionFlattener.flatten(body)
            { sections: sections, total: sections.length, notes: notes_body?(body) }
          end

          def notes_body?(body)
            body.attributes['name'].to_s.casecmp('notes').zero?
          end

          def report_body_progress(index, total, chapter_number)
            report("Building chapter #{chapter_number}...", progress: 0.3 + (0.4 * ratio(index, total)))
          end

          def build_chapter_from_section(section, chapter_number, body_index, notes_body)
            Core::Models::Chapter.new(
              number: chapter_number.to_s,
              title: sanitize(resolved_section_title(section, chapter_number, notes_body)),
              lines: nil,
              metadata: { format: :fb2, section_depth: section.depth, body_index: body_index },
              blocks: nil,
              raw_content: section_to_xml(section.element)
            )
          end

          def resolved_section_title(section, chapter_number, notes_body)
            title = section.title
            return 'Notes' if title.nil? && notes_body

            text = title.to_s.strip
            text.empty? ? "Chapter #{chapter_number}" : text
          end

          def build_toc_entries(chapters)
            Array(chapters).each_with_index.map do |chapter, index|
              Core::Models::TOCEntry.new(
                title: chapter.title || "Chapter #{index + 1}",
                href: nil,
                level: chapter.metadata.is_a?(Hash) ? (chapter.metadata[:section_depth] || 0) : 0,
                chapter_index: index,
                navigable: true
              )
            end
          end

          def extract_binary_resources(doc)
            binary_elements(doc).each_with_object({}) do |element, resources|
              decoded = decoded_binary_resource(element)
              next unless decoded

              resources[decoded[:id]] = decoded[:data]
            end
          end

          def binary_elements(doc)
            root = doc.root || doc
            root.elements.select { |child| child.name.to_s.casecmp('binary').zero? }
          end

          def decoded_binary_resource(element)
            id = element.attributes['id'].to_s.strip
            return nil if id.empty?

            base64_data = element.text.to_s.gsub(/\s+/, '')
            return nil if base64_data.empty?

            decoded = Base64.decode64(base64_data)
            decoded.force_encoding(Encoding::BINARY)
            { id: id, data: decoded }
          end

          def collect_bodies(doc)
            bodies = direct_body_children(doc)
            return bodies unless bodies.empty?

            doc.elements.to_a('//body')
          end

          def direct_body_children(doc)
            root = doc.root || doc
            root.elements.select { |child| child.name.to_s.casecmp('body').zero? }
          end

          def section_to_xml(element)
            return '' unless element

            output = +''
            REXML::Formatters::Default.new.write(element, output)
            output
          rescue Shoko::Error
            element.to_s
          end

          def error_chapter(message)
            Core::Models::Chapter.new(
              number: '1',
              title: 'Error',
              lines: [message],
              metadata: { format: :fb2 },
              blocks: nil,
              raw_content: nil
            )
          end

          def sanitize(text)
            Shoko::Shared::TextSanitizer.sanitize(text.to_s, preserve_newlines: false, preserve_tabs: false)
          rescue Shoko::Error
            text.to_s
          end
        end
      end
    end
  end
end
