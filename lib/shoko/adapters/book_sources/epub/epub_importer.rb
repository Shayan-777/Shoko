# frozen_string_literal: true

require 'rexml/document'

require_relative '../../../shared/errors'
require_relative '../../../shared/text_sanitizer'
require_relative '../archive/zip_reader'
require_relative '../../../core/book_formats/epub/html_processor'
require_relative '../../../core/book_formats/epub/rexml_safe_parser'
require_relative '../../../core/book_formats/epub/opf_processor'
require_relative '../../../core/book_formats/epub/xml_text_normalizer'
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

          DEFAULT_LANGUAGE = 'en_US'
          CONTAINER_PATH   = 'META-INF/container.xml'

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

          def import(epub_path)
            @epub_path = File.expand_path(epub_path)
            raise Shoko::FileNotFoundError, epub_path unless File.file?(@epub_path)

            report('Opening EPUB archive...', progress: 0.0)
            @archive_reader.open(@epub_path, runtime_config: @runtime_config) do |zip|
              report('Reading container.xml...', progress: 0.0)
              container_xml = read_container(zip)
              report('Locating OPF package...', progress: 0.0)
              opf_path = locate_opf_path(zip, container_xml)
              report('Parsing OPF metadata...', progress: 0.0)
              processor = Core::BookFormats::Epub::OPFProcessor.new(opf_path, zip: zip,
                                                                              instrumentation: @instrumentation)

              metadata = processor.extract_metadata
              report('Building manifest...', progress: 0.0)
              manifest = processor.build_manifest_map
              report('Reading navigation data...', progress: 0.0)
              chapter_titles = processor.extract_chapter_titles(manifest)

              chapters_data = build_chapters(zip, opf_path, processor, manifest, chapter_titles)
              chapters      = chapters_data[:chapters]
              chapter_hrefs = chapters_data[:hrefs]
              spine         = chapters_data[:spine]

              report('Building table of contents...', progress: 0.0)
              toc_entries = build_toc_entries(chapters, processor.toc_entries, chapter_hrefs, opf_path)
              report('Extracting resources...', progress: 0.0) if @extract_resources
              resources = @extract_resources ? extract_resources(zip, opf_path, manifest) : {}

              Core::Models::BookData.new(
                title: metadata[:title] || fallback_title(@epub_path),
                language: metadata[:language] || DEFAULT_LANGUAGE,
                authors: Array(metadata[:authors]).map(&:to_s),
                chapters: chapters,
                toc_entries: toc_entries,
                opf_path: opf_path,
                spine: spine,
                chapter_hrefs: chapter_hrefs,
                resources: resources,
                metadata: metadata,
                container_path: CONTAINER_PATH,
                container_xml: container_xml
              )
            end
          rescue Zip::Error, REXML::ParseException => e
            raise Shoko::BookParseError.new(e.message, epub_path)
          end

          private

          def read_container(zip)
            instrument('epub.read_container') do
              normalize_text(zip.read(CONTAINER_PATH))
            end
          rescue Zip::Error
            raise Shoko::BookParseError.new('Missing META-INF/container.xml', @epub_path)
          end

          def locate_opf_path(zip, container_xml)
            instrument('epub.locate_opf') do
              doc = Core::BookFormats::Epub::REXMLSafeParser.parse(container_xml)
              elems = doc.elements
              rootfile = elems['//rootfile'] || elems['//container:rootfile']
              candidate = rootfile&.attributes&.[]('full-path')
              return candidate if candidate && zip.find_entry(candidate)
            end

            if (match = container_xml.to_s.match(/full-path=["']([^"']+)["']/i))
              candidate = match[1]
              return candidate if zip.find_entry(candidate)
            end

            raise Shoko::BookParseError.new('Unable to locate OPF file', @epub_path)
          rescue REXML::ParseException => e
            raise Shoko::BookParseError.new("Invalid container.xml: #{e.message}", @epub_path)
          end

          def build_chapters(zip, opf_path, processor, manifest, chapter_titles)
            chapters = []
            hrefs    = []
            spine    = []

            items = []
            processor.process_spine(manifest, chapter_titles) { |item| items << item }
            total = items.length

            if total.positive?
              report("Extracting HTML (0/#{total})...", progress: 0.0)
            else
              report('Extracting HTML...', progress: 0.0)
            end

            items.each_with_index do |item, index|
              report(
                "Extracting HTML (#{index + 1}/#{total})...",
                progress: ratio(index + 1, total)
              )
              raw = read_text_entry(zip, item.file_path)
              resolved_href = resolve_href(opf_path, item.href)
              chapter = Core::Models::Chapter.new(
                number: item.number.to_s,
                title: extract_chapter_title(raw, item.number, item.title),
                lines: nil,
                metadata: { source_path: item.file_path, href: resolved_href },
                blocks: nil,
                raw_content: raw
              )

              chapters << chapter
              hrefs << resolved_href
              spine << item.file_path
            end

            { chapters:, hrefs:, spine: }
          end

          def build_toc_entries(chapters, toc_entries, chapter_hrefs, opf_path)
            href_to_index = {}
            chapter_hrefs.each_with_index do |href, idx|
              href_to_index[href] = idx if href
            end

            Array(toc_entries).map do |entry|
              title = entry[:title]
              href  = entry[:href]
              level = entry[:level].to_i

              target = resolve_toc_target(opf_path, entry)
              chapter_index = href_to_index[target]
              if chapter_index && (chapter = chapters[chapter_index]) && chapter.title.to_s.strip.empty?
                chapter.title = title
              end

              Core::Models::TOCEntry.new(
                title: title,
                href: href,
                level: level,
                chapter_index: chapter_index,
                navigable: !chapter_index.nil?
              )
            end
          end

          def resolve_toc_target(opf_path, entry)
            return nil unless entry

            return entry[:target].to_s if entry.is_a?(Hash) && entry[:target]

            href = entry.is_a?(Hash) ? entry[:href] : nil
            return nil unless href

            core = href.to_s.split('#', 2).first.to_s
            return nil if core.empty?

            source_path = entry.is_a?(Hash) ? entry[:source_path] : nil
            base_path = (source_path || opf_path).to_s
            base_dir = File.dirname(base_path)
            File.expand_path(File.join('/', base_dir, core), '/').sub(%r{^/}, '')
          end

          def extract_resources(zip, opf_path, manifest)
            resources = {}

            manifest.each_value do |href|
              rel = href.to_s
              next if rel.empty?

              path = resolve_href(opf_path, rel)
              next unless zip.find_entry(path)

              resources[path] = read_binary_entry(zip, path)
            end
            resources
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
            Core::BookFormats::Epub::XmlTextNormalizer.normalize(content)
          end

          def resolve_href(opf_path, href)
            return nil unless href

            base = File.dirname(opf_path)
            root = File.expand_path(File.join('/', base, href), '/')
            root.sub(%r{^/}, '')
          end

          def extract_chapter_title(raw_content, number, hinted_title)
            hinted = hinted_title.to_s.strip
            return hinted unless hinted.empty?

            Core::BookFormats::Epub::HTMLProcessor.extract_title(raw_content) || "Chapter #{number}"
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
