# frozen_string_literal: true

require 'rexml/document'

require_relative '../../../shared/errors'
require_relative '../../../shared/text_sanitizer'
require_relative '../archive/zip_reader'
require_relative '../../../adapters/book_sources/epub/parser/html_processor'
require_relative '../../../adapters/book_sources/epub/parser/rexml_safe_parser'
require_relative '../../../adapters/book_sources/epub/parser/opf_processor'
require_relative '../../../adapters/book_sources/epub/parser/xml_text_normalizer'
require_relative 'epub_importer/document_building'
require_relative '../../../core/models/book_data'
require_relative '../../../core/models/chapter'
require_relative '../../../core/models/toc_entry'
require_relative '../../support/lifecycle_helpers'
module Shoko
  module Adapters
    module BookSources
      module Epub
        # Imports an EPUB archive into an in-memory representation that can be
        # serialized using {EpubCache}. Responsible for extracting metadata,
        # chapters, and table-of-contents entries in a consistent schema.
        #
        # Binary resources (images, stylesheets, etc.) are intentionally not extracted
        # by default since the reader currently renders image placeholders and does
        # not consume the raw bytes. Optional consumers (e.g. Kitty image rendering)
        # should load resources on-demand.
        class EpubImporter
          include Shoko::Adapters::Support::LifecycleHelpers
          include DocumentBuilding

          DEFAULT_LANGUAGE = 'en_US'
          CONTAINER_PATH   = 'META-INF/container.xml'

          def initialize(formatting_service: nil, extract_resources: false, progress_reporter: nil,
                         instrumentation: nil, runtime_config: nil,
                         archive_reader: Shoko::Adapters::BookSources::Archive::ZipReader)
            @formatting_service = formatting_service
            @extract_resources = extract_resources ? true : false
            @progress_reporter = progress_reporter
            @instrumentation = instrumentation
            @runtime_config = runtime_config
            @archive_reader = archive_reader
          end

          def import(epub_path)
            @epub_path = validated_epub_path(epub_path)

            report('Opening EPUB archive...', progress: 0.0)
            @archive_reader.open(@epub_path, runtime_config: @runtime_config) { |zip| import_archive(zip) }
          rescue Zip::Error, REXML::ParseException => e
            raise Shoko::BookParseError.new(e.message, epub_path)
          end

          private

          def validated_epub_path(epub_path)
            path = File.expand_path(epub_path)
            raise Shoko::FileNotFoundError, epub_path unless File.file?(path)

            path
          end

          def import_archive(zip)
            context = archive_context(zip)
            chapters_data = archive_chapters(zip, context)
            report('Building table of contents...', progress: 0.0)
            toc_entries = archive_toc_entries(chapters_data, context)
            build_book_data(
              metadata: context[:metadata],
              chapters: chapters_data[:chapters],
              toc_entries: toc_entries,
              opf_path: context[:opf_path],
              spine: chapters_data[:spine],
              chapter_hrefs: chapters_data[:hrefs],
              resources: archive_resources(zip, context[:opf_path], context[:manifest]),
              container_xml: context[:container_xml]
            )
          end

          def archive_context(zip)
            container_xml = reported_container_xml(zip)
            opf_path = reported_opf_path(zip, container_xml)
            processor = reported_processor(opf_path, zip)
            manifest = reported_manifest(processor)
            {
              container_xml: container_xml,
              opf_path: opf_path,
              processor: processor,
              metadata: processor.extract_metadata,
              manifest: manifest,
              chapter_titles: reported_chapter_titles(processor, manifest),
            }
          end

          def archive_chapters(zip, context)
            items = spine_items(context[:processor], context[:manifest], context[:chapter_titles])
            build_chapters(zip, context[:opf_path], items)
          end

          def archive_toc_entries(chapters_data, context)
            build_toc_entries(
              chapters_data[:chapters],
              context[:processor].toc_entries,
              chapters_data[:hrefs],
              context[:opf_path]
            )
          end

          def reported_container_xml(zip)
            report('Reading container.xml...', progress: 0.0)
            read_container(zip)
          end

          def reported_opf_path(zip, container_xml)
            report('Locating OPF package...', progress: 0.0)
            locate_opf_path(zip, container_xml)
          end

          def reported_processor(opf_path, zip)
            report('Parsing OPF metadata...', progress: 0.0)
            build_processor(opf_path, zip)
          end

          def reported_manifest(processor)
            report('Building manifest...', progress: 0.0)
            processor.build_manifest_map
          end

          def reported_chapter_titles(processor, manifest)
            report('Reading navigation data...', progress: 0.0)
            processor.extract_chapter_titles(manifest)
          end

          def build_processor(opf_path, zip)
            Adapters::BookSources::Epub::OPFProcessor.new(opf_path, zip: zip, instrumentation: @instrumentation)
          end

          def archive_resources(zip, opf_path, manifest)
            return {} unless @extract_resources

            report('Extracting resources...', progress: 0.0)
            extract_resources(zip, opf_path, manifest)
          end

          def extract_chapter_title(raw_content, number, hinted_title)
            hinted = hinted_title.to_s.strip
            return hinted unless hinted.empty?

            Adapters::BookSources::Epub::HTMLProcessor.extract_title(raw_content) || "Chapter #{number}"
          end

          def fallback_title(path)
            fallback_title_from_path(path)
          end

          def ratio(done, total)
            denom = [total.to_f, 1.0].max
            done.to_f / denom
          end

          # Archive access, entry reads, and OPF location helpers.
          def read_container(zip)
            instrument('epub.read_container') do
              normalize_text(zip.read(CONTAINER_PATH))
            end
          rescue Zip::Error
            raise Shoko::BookParseError.new('Missing META-INF/container.xml', @epub_path)
          end

          def locate_opf_path(zip, container_xml)
            located = instrument('epub.locate_opf') do
              rootfile_candidate(zip, container_xml)
            end
            return located if located

            matched = matching_container_path(zip, container_xml)
            return matched if matched

            raise Shoko::BookParseError.new('Unable to locate OPF file', @epub_path)
          rescue REXML::ParseException => e
            raise Shoko::BookParseError.new("Invalid container.xml: #{e.message}", @epub_path)
          end

          def rootfile_candidate(zip, container_xml)
            doc = Adapters::BookSources::Epub::REXMLSafeParser.parse(container_xml)
            elems = doc.elements
            rootfile = elems['//rootfile'] || elems['//container:rootfile']
            candidate = rootfile&.attributes&.[]('full-path')
            candidate if candidate && zip.find_entry(candidate)
          end

          def matching_container_path(zip, container_xml)
            match = container_xml.to_s.match(/full-path=["']([^"']+)["']/i)
            candidate = match && match[1]
            candidate if candidate && zip.find_entry(candidate)
          end

          def extract_resources(zip, opf_path, manifest)
            manifest.each_with_object({}) do |(_, href), resources|
              path = resolved_manifest_path(opf_path, href)
              next unless path && zip.find_entry(path)

              resources[path] = read_binary_entry(zip, path)
            end
          end

          def resolved_manifest_path(opf_path, href)
            rel = href.to_s
            return nil if rel.empty?

            resolve_href(opf_path, rel)
          end

          def read_text_entry(zip, path)
            instrument('epub.read_text_entry') do
              content = zip.read(path)
              normalize_text(content)
            end
          end

          def read_binary_entry(zip, path)
            instrument('epub.read_binary_entry') do
              data = zip.read(path)
              data.force_encoding(Encoding::BINARY)
            end
          end

          def normalize_text(content)
            Adapters::BookSources::Epub::XmlTextNormalizer.normalize(content)
          end

          def resolve_href(opf_path, href)
            return nil unless href

            base = File.dirname(opf_path)
            root = File.expand_path(File.join('/', base, href), '/')
            root.sub(%r{^/}, '')
          end
        end
      end
    end
  end
end
