# frozen_string_literal: true

require 'rexml/document'

require_relative '../../../shared/errors'
require_relative '../archive/zip_reader'
require_relative '../../../core/models/chapter'
require_relative '../../../core/models/toc_entry'
require_relative '../../../core/models/book_data'
require_relative '../../../shared/text_sanitizer'
require_relative '../../../core/book_formats/fb2/fb2_section_flattener'
require_relative '../../../core/book_formats/fb2/fb2_metadata_extractor'
require_relative '../../../core/book_formats/fb2/metadata_parser'
require_relative '../../../core/book_formats/fb2/fb2_inline_parser'
require_relative '../../../core/book_formats/format_registry'
require_relative '../../support/lifecycle_helpers'

module Shoko
  module Adapters
    module BookSources
      module Fb2
        # Imports an FB2 (FictionBook 2) file into the same in-memory
        # {Core::Models::BookData} representation used by all formats,
        # so the entire downstream pipeline (cache, formatting, rendering) works
        # unchanged.
        #
        # Handles both plain .fb2 (XML) and .fb2.zip (zipped) files.
        class Fb2Importer
          include Shoko::Adapters::Support::LifecycleHelpers

          DEFAULT_LANGUAGE = 'en_US'

          def initialize(formatting_service: nil, extract_resources: false, progress_reporter: nil, instrumentation: nil,
                         runtime_config: nil,
                         archive_reader: Shoko::Adapters::BookSources::Archive::ZipReader)
            @formatting_service = formatting_service
            @extract_resources = !!extract_resources
            @progress_reporter = progress_reporter
            @instrumentation = instrumentation
            @runtime_config = runtime_config
            @archive_reader = archive_reader
          end

          # @param path [String] path to .fb2 or .fb2.zip file
          # @return [Core::Models::BookData]
          def import(path)
            @fb2_path = File.expand_path(path)
            raise Shoko::FileNotFoundError, path unless File.file?(@fb2_path)

            report('Reading FB2 file...', progress: 0.0)
            xml = read_fb2_xml(@fb2_path)
            raise Shoko::BookParseError.new('Unable to read FB2 content', @fb2_path) unless xml

            report('Parsing FB2 document...', progress: 0.1)
            doc = instrument('fb2.parse') { parse_xml(xml) }

            report('Extracting metadata...', progress: 0.2)
            metadata = instrument('fb2.metadata') { extract_metadata(doc) }

            report('Building chapters...', progress: 0.3)
            chapters_data = instrument('fb2.chapters') { build_chapters(doc) }

            report('Building table of contents...', progress: 0.7)
            chapters = chapters_data[:chapters]
            toc_entries = build_toc_entries(chapters)

            report('Extracting resources...', progress: 0.8) if @extract_resources
            resources = if @extract_resources
                          instrument('fb2.resources') { extract_binary_resources(doc) }
                        else
                          {}
                        end

            report('Finalizing...', progress: 0.9)
            Core::Models::BookData.new(
              title: metadata[:title] || fallback_title(@fb2_path),
              language: metadata[:language] || DEFAULT_LANGUAGE,
              authors: Array(metadata[:authors]).map(&:to_s),
              chapters: chapters,
              toc_entries: toc_entries,
              opf_path: nil,
              spine: [],
              chapter_hrefs: [],
              resources: resources,
              metadata: metadata,
              container_path: nil,
              container_xml: nil,
              format_data: { format: :fb2, source_type: detect_source_type(@fb2_path) }
            )
          rescue Shoko::Error
            raise
          rescue REXML::ParseException => e
            raise Shoko::BookParseError.new(e.message, path)
          rescue StandardError => e
            raise Shoko::BookParseError.new(e.message, path)
          end

          private

          def read_fb2_xml(path)
            lower = path.downcase
            if lower.end_with?('.fb2.zip')
              read_from_zip(path)
            else
              content = File.read(path)
              normalize_encoding(content)
            end
          end

          def read_from_zip(path)
            @archive_reader.open(path, runtime_config: @runtime_config) do |zip|
              entry = zip.entries.find { |e| e.name.downcase.end_with?('.fb2') }
              raise Shoko::BookParseError.new('No .fb2 file found inside archive', path) unless entry

              normalize_encoding(zip.read(entry.name))
            end
          end

          def normalize_encoding(content)
            return content if content.nil?

            # Try UTF-8 first
            content.force_encoding('UTF-8')
            return content if content.valid_encoding?

            # Try to detect from XML declaration
            if (match = content.match(/encoding=["']([^"']+)["']/i))
              begin
                return content.encode('UTF-8', match[1])
              rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
                nil
              end
            end

            # Last resort: force to UTF-8 replacing invalid bytes
            content.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
          end

          def parse_xml(xml)
            # Strip default namespace declarations so plain element name lookups work.
            # FB2 declares xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" which
            # causes REXML XPath and elements[] to miss every element.
            stripped = xml.gsub(/\s+xmlns\s*=\s*["'][^"']*["']/, '')
            REXML::Document.new(stripped)
          end

          def find_element(context, path)
            parts = path.split('/')
            current = context.is_a?(REXML::Document) ? context.root : context
            return nil unless current

            parts.each do |part|
              current = current.elements.detect { |el| el.name.to_s.downcase == part.downcase }
              return nil unless current
            end
            current
          end

          def extract_metadata(doc)
            canonical = Core::BookFormats::Fb2::MetadataParser.parse_document(doc)
            title_info = find_element(doc, 'description/title-info') ||
                         find_element(doc, 'FictionBook/description/title-info')
            genre = element_text(title_info, 'genre')

            {
              title: canonical[:title],
              authors: canonical[:authors],
              language: canonical[:language],
              year: canonical[:year],
              genre: genre,
            }.compact
          end

          def build_chapters(doc)
            # FB2 may have multiple <body> elements (main + notes/comments)
            bodies = collect_bodies(doc)
            return { chapters: [error_chapter('No content found')] } if bodies.empty?

            chapters = []
            bodies.each_with_index do |body, body_idx|
              body_name = body.attributes['name']
              is_notes = body_name.to_s.downcase == 'notes'

              sections = Core::BookFormats::Fb2::Fb2SectionFlattener.flatten(body)
              total = sections.length

              sections.each_with_index do |section, idx|
                report("Building chapter #{chapters.length + 1}...",
                       progress: 0.3 + 0.4 * ratio(idx + 1, total))

                title = section.title
                title = "Notes" if title.nil? && is_notes
                title = "Chapter #{chapters.length + 1}" if title.nil? || title.strip.empty?

                # Serialize the section element back to XML for raw_content
                raw_xml = section_to_xml(section.element)

                chapters << Core::Models::Chapter.new(
                  number: (chapters.length + 1).to_s,
                  title: sanitize(title),
                  lines: nil,
                  metadata: { format: :fb2, section_depth: section.depth, body_index: body_idx },
                  blocks: nil,
                  raw_content: raw_xml
                )
              end
            end

            chapters = [error_chapter('No chapters found')] if chapters.empty?
            { chapters: chapters }
          end

          def build_toc_entries(chapters)
            chapters.each_with_index.map do |chapter, idx|
              depth = chapter.metadata.is_a?(Hash) ? (chapter.metadata[:section_depth] || 0) : 0
              Core::Models::TOCEntry.new(
                title: chapter.title || "Chapter #{idx + 1}",
                href: nil,
                level: depth,
                chapter_index: idx,
                navigable: true
              )
            end
          end

          def extract_binary_resources(doc)
            resources = {}
            root = doc.root || doc

            root.elements.each do |child|
              next unless child.name.to_s.downcase == 'binary'

              id = child.attributes['id']
              next unless id && !id.strip.empty?

              content_type = child.attributes['content-type']
              base64_data = child.text.to_s.gsub(/\s+/, '')
              next if base64_data.empty?

              begin
                decoded = Base64.decode64(base64_data)
                decoded.force_encoding(Encoding::BINARY)
                resources[id] = decoded
              rescue StandardError
                next
              end
            end

            resources
          end

          def collect_bodies(doc)
            bodies = []
            root = doc.root || doc

            # Try direct children of root
            root.elements.each do |child|
              bodies << child if child.name.to_s.downcase == 'body'
            end

            # Fallback: search deeper
            if bodies.empty?
              doc.elements.each('//body') { |body| bodies << body }
            end

            bodies
          end

          def section_to_xml(element)
            return '' unless element

            output = +''
            formatter = REXML::Formatters::Default.new
            formatter.write(element, output)
            output
          rescue StandardError
            element.to_s
          end

          def element_text(parent, tag)
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
            Shoko::Shared::TextSanitizer.sanitize(
              text.to_s, preserve_newlines: false, preserve_tabs: false
            )
          rescue StandardError
            text.to_s
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
        end
      end
    end
  end
end

require 'base64'
