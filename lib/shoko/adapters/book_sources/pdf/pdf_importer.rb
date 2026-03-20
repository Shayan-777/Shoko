# frozen_string_literal: true

require_relative '../../../shared/errors'
require_relative '../../../core/models/chapter'
require_relative '../../../core/models/toc_entry'
require_relative '../../../core/models/book_data'
require_relative '../../../shared/text_sanitizer'
require_relative '../../../adapters/book_sources/pdf/parser/pdf_reader'
require_relative '../../../adapters/book_sources/pdf/parser/pdf_text_extractor'
require_relative '../../../adapters/book_sources/pdf/parser/pdf_metadata_extractor'
require_relative '../../../adapters/book_sources/pdf/parser/metadata_parser'
require_relative '../../../adapters/book_sources/format_registry'
require_relative '../../support/lifecycle_helpers'
require_relative 'importer/book_data_helpers'
require_relative 'importer/metadata_normalizer'
require_relative 'importer/page_extraction_coordinator'
require_relative 'importer/title_decoding'

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
          include Importer::BookDataHelpers
          include Importer::TitleDecoding

          DEFAULT_LANGUAGE = 'en_US'
          PAGES_PER_AUTO_CHAPTER = 20

          def initialize(formatting_service: nil, extract_resources: false, progress_reporter: nil,
                         instrumentation: nil)
            @formatting_service = formatting_service
            @extract_resources = extract_resources ? true : false
            @progress_reporter = progress_reporter
            @instrumentation = instrumentation
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
            chapters = []
            total = outlines.size

            outlines.each_with_index do |entry, idx|
              context = { outlines: outlines, total: total, chapter_number: chapters.size + 1 }
              chapter = outline_chapter(entry, idx, context)
              chapters << chapter if chapter
            end
            chapters
          end

          def outline_chapter(entry, idx, context)
            start_page = entry[:page_idx]
            return nil unless start_page

            end_page = find_chapter_end_page(context[:outlines], idx, start_page)
            report(
              "Building chapter #{idx + 1}/#{context[:total]}...",
              progress: chapter_progress(idx, context[:total])
            )
            title = sanitize(entry[:title] || "Chapter #{context[:chapter_number]}")

            build_chapter(
              number: context[:chapter_number],
              title: title,
              start_page: start_page,
              end_page: end_page,
              depth: entry[:depth]
            )
          end

          def chapter_progress(idx, total)
            0.3 + (0.6 * (idx.to_f / [total, 1].max))
          end

          def find_chapter_end_page(outlines, current_idx, start_page)
            ((current_idx + 1)...outlines.size).each do |i|
              next_page = outlines[i][:page_idx]
              next unless next_page&.positive?

              return [next_page - 1, start_page].max
            end

            @pages.size - 1
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
        end
      end
    end
  end
end
