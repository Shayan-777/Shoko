# frozen_string_literal: true

require 'rexml/document'
require 'shoko/shared/errors'
require 'shoko/shared/text_sanitizer'
require_relative '../archive/zip_reader'
require 'shoko/adapters/book_sources/epub/parser/html_processor'
require 'shoko/adapters/book_sources/epub/parser/rexml_safe_parser'
require 'shoko/adapters/book_sources/epub/parser/opf_processor'
require 'shoko/adapters/book_sources/epub/parser/xml_text_normalizer'
require 'shoko/core/models/book_data'
require 'shoko/core/models/chapter'
require 'shoko/core/models/toc_entry'
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

          def build_chapters(zip, opf_path, items)
            report_initial_chapter_progress(items.length)

            items.each_with_index.with_object({ chapters: [], hrefs: [], spine: [] }) do |(item, index), acc|
              report_chapter_progress(index, items.length)
              chapter = chapter_from_item(zip, opf_path, item)
              append_chapter(acc, chapter, item.file_path)
            end
          end

          def spine_items(processor, manifest, chapter_titles)
            items = []
            processor.process_spine(manifest, chapter_titles) { |item| items << item }
            items
          end

          def report_initial_chapter_progress(total)
            message = if total.positive?
                        "Extracting HTML (0/#{total})..."
                      else
                        'Extracting HTML...'
                      end
            report(message, progress: 0.0)
          end

          def report_chapter_progress(index, total)
            report("Extracting HTML (#{index + 1}/#{total})...", progress: ratio(index + 1, total))
          end

          def append_chapter(acc, chapter, spine_path)
            acc[:chapters] << chapter
            acc[:hrefs] << chapter.metadata[:href]
            acc[:spine] << spine_path
          end

          def chapter_from_item(zip, opf_path, item)
            raw = read_text_entry(zip, item.file_path)
            resolved_href = resolve_href(opf_path, item.href)
            Core::Models::Chapter.new(
              number: item.number.to_s,
              title: extract_chapter_title(raw, item.number, item.title),
              lines: nil,
              metadata: { source_path: item.file_path, href: resolved_href },
              blocks: nil,
              raw_content: raw
            )
          end

          def build_toc_entries(chapters, toc_entries, chapter_hrefs, opf_path)
            href_to_index = chapter_href_index(chapter_hrefs)

            Array(toc_entries).map do |entry|
              build_toc_entry(chapters, href_to_index, opf_path, entry)
            end
          end

          def chapter_href_index(chapter_hrefs)
            chapter_hrefs.each_with_index.with_object({}) do |(href, index), mapping|
              mapping[href] = index if href
            end
          end

          def build_toc_entry(chapters, href_to_index, opf_path, entry)
            title = entry[:title]
            href = entry[:href]
            level = entry[:level].to_i
            chapter_index = href_to_index[resolve_toc_target(opf_path, entry)]
            apply_toc_title!(chapters, chapter_index, title)

            Core::Models::TOCEntry.new(
              title: title,
              href: href,
              level: level,
              chapter_index: chapter_index,
              navigable: !chapter_index.nil?
            )
          end

          def apply_toc_title!(chapters, chapter_index, title)
            return unless chapter_index

            chapter = chapters[chapter_index]
            chapter.title = title if chapter && chapter.title.to_s.strip.empty?
          end

          def resolve_toc_target(opf_path, entry)
            return nil unless entry
            return entry[:target].to_s if entry.is_a?(Hash) && entry[:target]

            href = entry.is_a?(Hash) ? entry[:href] : nil
            core_href = href.to_s.split('#', 2).first
            return nil if core_href.empty?

            base_path = toc_source_path(entry, opf_path)
            base_dir = File.dirname(base_path)
            File.expand_path(File.join('/', base_dir, core_href), '/').sub(%r{^/}, '')
          end

          def toc_source_path(entry, opf_path)
            source_path = entry.is_a?(Hash) ? entry[:source_path] : nil
            (source_path || opf_path).to_s
          end

          def build_book_data(metadata:, chapters:, toc_entries:, opf_path:, spine:, chapter_hrefs:, resources:,
                              container_xml:)
            Core::Models::BookData.new(
              title: metadata[:title] || fallback_title(@epub_path),
              language: metadata[:language] || DEFAULT_LANGUAGE,
              authors: Array(metadata[:authors]).map(&:to_s),
              chapters: chapters,
              toc_entries: toc_entries,
              resources: resources,
              metadata: metadata,
              format_data: epub_format_data(
                opf_path: opf_path,
                spine: spine,
                chapter_hrefs: chapter_hrefs,
                container_xml: container_xml
              )
            )
          end

          def epub_format_data(opf_path:, spine:, chapter_hrefs:, container_xml:)
            {
              format: :epub,
              source_type: :epub,
              epub: {
                opf_path: opf_path,
                spine: spine,
                chapter_hrefs: chapter_hrefs,
                container_path: CONTAINER_PATH,
                container_xml: container_xml,
              },
            }
          end
        end
      end
    end
  end
end
