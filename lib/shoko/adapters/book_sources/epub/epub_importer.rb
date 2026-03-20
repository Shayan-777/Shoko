# frozen_string_literal: true

require 'rexml/document'

require_relative '../../../shared/errors'
require_relative '../../../shared/text_sanitizer'
require_relative '../archive/zip_reader'
require_relative '../../../adapters/book_sources/epub/parser/html_processor'
require_relative '../../../adapters/book_sources/epub/parser/rexml_safe_parser'
require_relative '../../../adapters/book_sources/epub/parser/opf_processor'
require_relative '../../../adapters/book_sources/epub/parser/xml_text_normalizer'
require_relative 'epub_importer/archive_support'
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
          include ArchiveSupport
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
        end
      end
    end
  end
end
