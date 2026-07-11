# frozen_string_literal: true

require 'shoko/shared/errors'
require 'shoko/core/models/chapter'
require 'shoko/core/models/toc_entry'
require 'shoko/core/models/book_data'
require 'shoko/shared/text_sanitizer'
require 'shoko/adapters/book_sources/pdf/parser/pdf_reader'
require 'shoko/adapters/book_sources/pdf/parser/pdf_text_extractor'
require 'shoko/adapters/book_sources/pdf/parser/pdf_metadata_extractor'
require 'shoko/adapters/book_sources/pdf/parser/metadata_parser'
require 'shoko/adapters/book_sources/format_registry'
require_relative '../../support/lifecycle_helpers'
require_relative 'importer/metadata_normalizer'
require_relative 'importer/page_extraction_coordinator'

module Shoko
  module Adapters
    module BookSources
      module Pdf
        # Imports a PDF file into the same in-memory
        # {Core::Models::BookData} representation used by all formats,
        # so the entire downstream pipeline (cache, formatting, rendering) works
        # unchanged.
        #
        # Uses PDF Outline (bookmark) entries for chapter boundaries. Falls back to
        # grouping pages when no outlines are present.
        class PdfImporter
          include Shoko::Adapters::Support::LifecycleHelpers

          DEFAULT_LANGUAGE = 'en_US'
          PAGES_PER_AUTO_CHAPTER = 20

          # `runtime_config` is part of the uniform importer construction
          # contract (see Ports::Outbound::BookImporterResolver); PDF has no
          # archive limits to configure, so it is accepted and unused.
          def initialize(formatting_service: nil, extract_resources: false, progress_reporter: nil,
                         instrumentation: nil, runtime_config: nil)
            @formatting_service = formatting_service
            @extract_resources = extract_resources ? true : false
            @progress_reporter = progress_reporter
            @instrumentation = instrumentation
            @runtime_config = runtime_config
          end

          # @param path [String] path to .pdf file
          # @return [Core::Models::BookData]
          def import(path)
            prepare_import(path)
            metadata = run_step('Extracting metadata...', 0.1, 'pdf.metadata') { extract_metadata }
            outlines = run_step('Reading outlines...', 0.2, 'pdf.outlines') { read_outlines }
            chapters = run_step('Building chapters...', 0.3, 'pdf.chapters') { build_chapters(outlines) }
            toc_entries = build_toc_entries(outlines, chapters)
            build_book_data(metadata, chapters, toc_entries)
          rescue Shoko::Error => e
            raise if e.is_a?(Shoko::FileNotFoundError) || e.is_a?(Shoko::MalformedBookInputError)

            raise Shoko::BookParseError.new(e.message, path)
          end

          private

          def prepare_import(path)
            @pdf_path = File.expand_path(path)
            raise Shoko::FileNotFoundError, path unless File.file?(@pdf_path)

            report('Reading PDF file...', progress: 0.0)
            @reader = instrument('pdf.reader') { Adapters::BookSources::Pdf::PdfReader.new(File.binread(@pdf_path)) }
            @extractor = Adapters::BookSources::Pdf::PdfTextExtractor.new(@reader)
            @pages = @reader.page_object_numbers
            @page_extraction = nil

            raise Shoko::BookParseError.new('No pages found in PDF', @pdf_path) if @pages.empty?
          end

          def run_step(message, progress, metric_name, &)
            report(message, progress: progress)
            instrument(metric_name, &)
          end

          def extract_metadata
            info_raw = info_object_raw
            return {} unless info_raw

            canonical = Adapters::BookSources::Pdf::MetadataParser.parse(
              title: @reader.dict_value(info_raw, 'Title'),
              author: @reader.dict_value(info_raw, 'Author'),
              creation_date: @reader.dict_value(info_raw, 'CreationDate')
            )
            Importer::MetadataNormalizer.normalize(canonical)
          end

          def info_object_raw
            info_num = @reader.info_obj_num
            return nil unless info_num

            @reader.read_object_raw(info_num)
          end

          # Read the PDF outline (bookmark) tree.
          # @return [Array<Hash>] flat list of {title:, page_idx:, depth:}
          def read_outlines
            first_num = first_outline_object_number
            return [] unless first_num

            page_index = build_page_index
            entries = []
            walk_outlines(first_num, 0, entries, page_index)
            entries
          end

          def first_outline_object_number
            root_raw = @reader.read_object_raw(@reader.root_obj_num)
            return nil unless root_raw

            outlines_num = @reader.resolve_ref(@reader.dict_value(root_raw, 'Outlines'))
            return nil unless outlines_num

            outlines_raw = @reader.read_object_raw(outlines_num)
            return nil unless outlines_raw

            @reader.resolve_ref(@reader.dict_value(outlines_raw, 'First'))
          end

          def build_page_index
            index = {}
            @pages.each_with_index { |obj_num, idx| index[obj_num] = idx }
            index
          end

          def walk_outlines(obj_num, depth, entries, page_index)
            safety = 0
            current_num = obj_num
            while current_num && safety < 500
              safety += 1
              raw = @reader.read_object_raw(current_num)
              break unless raw

              entries << outline_entry(raw, depth, page_index)
              walk_outline_children(raw, depth, entries, page_index)
              current_num = @reader.resolve_ref(@reader.dict_value(raw, 'Next'))
            end
          end

          def outline_entry(raw, depth, page_index)
            page_obj = resolve_outline_destination(raw)
            {
              title: decode_outline_title(@reader.dict_value(raw, 'Title')),
              page_idx: page_obj ? page_index[page_obj] : nil,
              depth: depth,
            }
          end

          def walk_outline_children(raw, depth, entries, page_index)
            child_num = @reader.resolve_ref(@reader.dict_value(raw, 'First'))
            walk_outlines(child_num, depth + 1, entries, page_index) if child_num
          end

          def resolve_outline_destination(raw)
            direct_outline_destination(raw) || action_outline_destination(raw)
          end

          def direct_outline_destination(raw)
            destination_object(@reader.dict_value(raw, 'Dest'))
          end

          def action_outline_destination(raw)
            action = @reader.dict_value(raw, 'A')
            return nil unless action

            action_num = @reader.resolve_ref(action)
            action_text = action_num ? @reader.read_object_raw(action_num) : action
            return nil unless action_text

            action_type = @reader.dict_value(action_text, 'S')
            return nil unless action_type.nil? || action_type == 'GoTo'

            destination_object(@reader.dict_value(action_text, 'D'))
          end

          def destination_object(value)
            match = value.to_s.match(/(\d+)\s+\d+\s+R/)
            match ? match[1].to_i : nil
          end

          def build_chapters(outlines)
            return build_auto_chapters if outlines.empty?

            chapters = build_outline_chapters(outlines)
            chapters.empty? ? build_auto_chapters : chapters
          end

          def build_outline_chapters(outlines)
            starts = distinct_chapter_starts(outlines)
            total = starts.size

            starts.each_with_index.map do |start, idx|
              report("Building chapter #{idx + 1}/#{total}...", progress: chapter_progress(idx, total))
              build_chapter(
                number: idx + 1,
                title: sanitize(start[:entry][:title] || "Chapter #{idx + 1}"),
                start_page: start[:start_page],
                end_page: start[:end_page],
                depth: start[:entry][:depth]
              )
            end
          end

          # Several outline bookmarks can point at the same page (e.g. multiple
          # section headings on one page). One chapter per page keeps page ranges
          # disjoint, so a page is never rendered in two chapters; every bookmark
          # still reaches the page through its TOC entry, and its heading is shown
          # in the page content.
          def distinct_chapter_starts(outlines)
            starts = []
            outlines.each do |entry|
              start_page = entry[:page_idx]
              next unless start_page
              next if starts.any? && start_page <= starts.last[:start_page]

              starts << { entry: entry, start_page: start_page }
            end
            assign_end_pages(starts)
          end

          def assign_end_pages(starts)
            starts.each_with_index.map do |start, idx|
              next_start = starts[idx + 1]
              end_page = next_start ? next_start[:start_page] - 1 : @pages.size - 1
              start.merge(end_page: [end_page, start[:start_page]].max)
            end
          end

          def chapter_progress(idx, total)
            0.3 + (0.6 * (idx.to_f / [total, 1].max))
          end

          def build_auto_chapters
            total_pages = @pages.size
            chapter_ranges(total_pages).each_with_index.map do |(start_page, end_page), idx|
              chapter_num = idx + 1
              report("Building chapter #{chapter_num}...", progress: auto_chapter_progress(start_page, total_pages))
              title = "Pages #{start_page + 1}-#{end_page + 1}"

              build_chapter(number: chapter_num, title: title, start_page: start_page, end_page: end_page)
            end
          end

          def build_chapter(number:, title:, start_page:, end_page:, depth: nil)
            metadata = { format: :pdf, start_page: start_page, end_page: end_page }
            metadata[:depth] = depth unless depth.nil?

            Core::Models::Chapter.new(
              number: number.to_s,
              title: title,
              lines: nil,
              metadata: metadata,
              blocks: nil,
              raw_content: extract_pages_text(start_page, end_page)
            )
          end

          def extract_pages_text(start_page, end_page)
            page_extraction.extract_text(start_page: start_page, end_page: end_page)
          end

          def page_extraction
            @page_extraction ||= Importer::PageExtractionCoordinator.new(
              pages: @pages,
              extractor: @extractor,
              file_path: @pdf_path
            )
          end

          def build_book_data(metadata, chapters, toc_entries)
            report('Finalizing...', progress: 0.9)
            Core::Models::BookData.new(**book_data_attributes(metadata, chapters, toc_entries))
          end

          def book_data_attributes(metadata, chapters, toc_entries)
            {
              title: metadata[:title] || fallback_title(@pdf_path),
              language: metadata[:language] || PdfImporter::DEFAULT_LANGUAGE,
              authors: Array(metadata[:authors]).map(&:to_s),
              chapters: chapters,
              toc_entries: toc_entries,
              resources: {},
              metadata: metadata,
              format_data: { format: :pdf },
            }
          end

          def build_toc_entries(outlines, chapters)
            return toc_entries_from_chapters(chapters) if outlines.empty?

            toc_entries_from_outlines(outlines, chapters)
          end

          def toc_entries_from_chapters(chapters)
            chapters.each_with_index.map do |chapter, idx|
              Core::Models::TOCEntry.new(
                title: chapter.title,
                href: nil,
                level: 0,
                chapter_index: idx,
                navigable: true
              )
            end
          end

          # Keeps every bookmark as a TOC entry, each pointing at the chapter that
          # actually contains its page (several bookmarks may share one chapter
          # now that same-page chapters are collapsed).
          def toc_entries_from_outlines(outlines, chapters)
            outlines.filter_map do |entry|
              chapter_index = chapter_index_for_page(chapters, entry[:page_idx])
              next unless chapter_index

              Core::Models::TOCEntry.new(
                title: sanitize(entry[:title] || 'Section'),
                href: nil,
                level: entry[:depth] || 0,
                chapter_index: chapter_index,
                navigable: true
              )
            end
          end

          def chapter_index_for_page(chapters, page)
            return nil if page.nil? || chapters.empty?

            chapters.index { |chapter| page_in_chapter?(chapter, page) } ||
              fallback_chapter_index(chapters, page)
          end

          def page_in_chapter?(chapter, page)
            meta = chapter.metadata
            page.between?(meta[:start_page].to_i, meta[:end_page].to_i)
          end

          def fallback_chapter_index(chapters, page)
            page < chapters.first.metadata[:start_page].to_i ? 0 : chapters.size - 1
          end

          def chapter_ranges(total_pages)
            ranges = []
            (0...total_pages).step(PdfImporter::PAGES_PER_AUTO_CHAPTER) do |start_page|
              end_page = [start_page + PdfImporter::PAGES_PER_AUTO_CHAPTER - 1, total_pages - 1].min
              ranges << [start_page, end_page]
            end
            ranges
          end

          def auto_chapter_progress(start_page, total_pages)
            0.3 + (0.6 * (start_page.to_f / [total_pages, 1].max))
          end

          def sanitize(text)
            Shoko::Shared::TextSanitizer.sanitize(text.to_s, preserve_newlines: false, preserve_tabs: false)
          end

          def decode_outline_title(raw_title)
            sanitize(decode_pdf_hex_text(raw_title))
          end

          def decode_pdf_hex_text(raw_title)
            text = raw_title.to_s.strip
            return text unless text.match?(/\A(?:[0-9A-Fa-f]{2}\s*)+\z/)

            decode_pdf_hex_bytes([text.delete(" \t\r\n")].pack('H*'))
          rescue ArgumentError, EncodingError
            raw_title.to_s
          end

          def decode_pdf_hex_bytes(bytes)
            return bytes_to_utf8(bytes.byteslice(2..)) if bytes.start_with?("\xFE\xFF".b)
            return bytes_to_utf8(bytes.byteslice(2..), encoding: Encoding::UTF_16LE) if bytes.start_with?("\xFF\xFE".b)
            if bytes.include?("\x00".b) && bytes.bytesize.even?
              return bytes_to_utf8(bytes, encoding: Encoding::UTF_16BE)
            end

            bytes_to_utf8(bytes)
          end

          def bytes_to_utf8(bytes, encoding: Encoding::UTF_8)
            return '' unless bytes

            bytes.dup.force_encoding(encoding).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
          rescue EncodingError
            bytes.dup.force_encoding(Encoding::UTF_8).scrub('')
          end

          def fallback_title(path)
            fallback_title_from_path(path) { |text| sanitize(text) }
          end
        end
      end
    end
  end
end
