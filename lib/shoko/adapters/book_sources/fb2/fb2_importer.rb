# frozen_string_literal: true

require 'base64'
require 'rexml/document'

require_relative '../../../shared/errors'
require_relative '../archive/zip_reader'
require_relative '../../../core/models/chapter'
require_relative '../../../core/models/toc_entry'
require_relative '../../../core/models/book_data'
require_relative '../../../shared/text_sanitizer'
require_relative '../../../adapters/book_sources/fb2/parser/fb2_section_flattener'
require_relative '../../../adapters/book_sources/fb2/parser/fb2_metadata_extractor'
require_relative '../../../adapters/book_sources/fb2/parser/metadata_parser'
require_relative '../../../adapters/book_sources/fb2/parser/fb2_inline_parser'
require_relative '../../../adapters/book_sources/format_registry'
require_relative 'fb2_importer/document_building'
require_relative '../../support/lifecycle_helpers'

module Shoko
  module Adapters
    module BookSources
      module Fb2
        # Imports an FB2 (FictionBook 2) file into the common BookData representation.
        # Handles both plain `.fb2` and zipped `.fb2.zip` sources.
        class Fb2Importer
          include Shoko::Adapters::Support::LifecycleHelpers
          include DocumentBuilding

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
        end
      end
    end
  end
end
