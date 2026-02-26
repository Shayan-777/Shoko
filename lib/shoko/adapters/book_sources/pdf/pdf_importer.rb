# frozen_string_literal: true

require 'json'

require_relative '../../../shared/errors'
require_relative '../../../core/models/chapter'
require_relative '../../../core/models/toc_entry'
require_relative '../../../core/models/book_data'
require_relative '../../../shared/text_sanitizer'
require_relative '../../../core/book_formats/pdf/pdf_reader'
require_relative '../../../core/book_formats/pdf/pdf_text_extractor'
require_relative '../../../core/book_formats/pdf/pdf_metadata_extractor'
require_relative '../../../core/book_formats/pdf/metadata_parser'
require_relative '../../../core/book_formats/format_registry'
require_relative '../../support/lifecycle_helpers'

module Shoko
  module Adapters::BookSources::Pdf
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

      def initialize(formatting_service: nil, extract_resources: false, progress_reporter: nil, instrumentation: nil)
        @formatting_service = formatting_service
        @extract_resources = !!extract_resources
        @progress_reporter = progress_reporter
        @instrumentation = instrumentation
      end

      # @param path [String] path to .pdf file
      # @return [Core::Models::BookData]
      def import(path)
        @pdf_path = File.expand_path(path)
        raise Shoko::FileNotFoundError, path unless File.file?(@pdf_path)

        report('Reading PDF file...', progress: 0.0)
        @reader = instrument('pdf.reader') { Core::BookFormats::Pdf::PdfReader.new(File.binread(@pdf_path)) }
        @extractor = Core::BookFormats::Pdf::PdfTextExtractor.new(@reader)
        @pages = @reader.page_object_numbers

        raise Shoko::BookParseError.new('No pages found in PDF', @pdf_path) if @pages.empty?

        report('Extracting metadata...', progress: 0.1)
        metadata = instrument('pdf.metadata') { extract_metadata }

        report('Reading outlines...', progress: 0.2)
        outlines = instrument('pdf.outlines') { read_outlines }

        report('Building chapters...', progress: 0.3)
        chapters = instrument('pdf.chapters') { build_chapters(outlines) }

        toc_entries = build_toc_entries(outlines, chapters)

        report('Finalizing...', progress: 0.9)
        Core::Models::BookData.new(
          title: metadata[:title] || fallback_title(@pdf_path),
          language: metadata[:language] || DEFAULT_LANGUAGE,
          authors: Array(metadata[:authors]).map(&:to_s),
          chapters: chapters,
          toc_entries: toc_entries,
          opf_path: nil,
          spine: [],
          chapter_hrefs: [],
          resources: {},
          metadata: metadata,
          container_path: nil,
          container_xml: nil,
          format_data: { format: :pdf }
        )
      rescue Shoko::Error
        raise
      rescue StandardError => e
        raise Shoko::BookParseError.new(e.message, path)
      end

      private

      def extract_metadata
        info_num = @reader.info_obj_num
        return {} unless info_num

        info_raw = @reader.read_object_raw(info_num)
        return {} unless info_raw

        canonical = Core::BookFormats::Pdf::MetadataParser.parse(
          title: @reader.dict_value(info_raw, 'Title'),
          author: @reader.dict_value(info_raw, 'Author'),
          creation_date: @reader.dict_value(info_raw, 'CreationDate')
        )
        authors = Array(canonical[:authors]).map(&:to_s).map(&:strip).reject(&:empty?)

        {
          title: canonical[:title],
          authors: authors,
          author_str: authors.join('; '),
          year: canonical[:year].to_s,
          language: canonical[:language],
        }.compact
      end

      # Read the PDF outline (bookmark) tree.
      # @return [Array<Hash>] flat list of {title:, page_idx:, depth:}
      def read_outlines
        root = @reader.read_object_raw(@reader.root_obj_num)
        return [] unless root

        outlines_ref = @reader.dict_value(root, 'Outlines')
        outlines_num = @reader.resolve_ref(outlines_ref)
        return [] unless outlines_num

        outlines_raw = @reader.read_object_raw(outlines_num)
        return [] unless outlines_raw

        first_ref = @reader.dict_value(outlines_raw, 'First')
        first_num = @reader.resolve_ref(first_ref)
        return [] unless first_num

        page_index = build_page_index
        entries = []
        walk_outlines(first_num, 0, entries, page_index)
        entries
      end

      def build_page_index
        index = {}
        @pages.each_with_index { |obj_num, idx| index[obj_num] = idx }
        index
      end

      def walk_outlines(obj_num, depth, entries, page_index)
        return unless obj_num

        safety = 0
        current_num = obj_num
        while current_num && safety < 500
          safety += 1
          raw = @reader.read_object_raw(current_num)
          break unless raw

          title = @reader.dict_value(raw, 'Title')
          page_obj = resolve_outline_destination(raw)

          page_idx = page_obj ? page_index[page_obj] : nil
          entries << { title: title, page_idx: page_idx, depth: depth }

          # Recurse into children
          first_child_ref = @reader.dict_value(raw, 'First')
          if first_child_ref
            child_num = @reader.resolve_ref(first_child_ref)
            walk_outlines(child_num, depth + 1, entries, page_index) if child_num
          end

          # Next sibling
          next_ref = @reader.dict_value(raw, 'Next')
          break unless next_ref

          current_num = @reader.resolve_ref(next_ref)
        end
      end

      # Resolve the destination page object number from an outline entry.
      # Handles both direct /Dest and /A (action) dictionaries.
      def resolve_outline_destination(raw)
        # Try direct /Dest first
        dest = @reader.dict_value(raw, 'Dest')
        if dest
          match = dest.match(/(\d+)\s+\d+\s+R/)
          return match[1].to_i if match
        end

        # Try /A action dictionary (GoTo action with /D destination)
        action = @reader.dict_value(raw, 'A')
        return nil unless action

        # If /A is a reference, resolve it
        action_num = @reader.resolve_ref(action)
        action_text = action_num ? @reader.read_object_raw(action_num) : action

        return nil unless action_text

        # Check for /S /GoTo (action type)
        action_type = @reader.dict_value(action_text, 'S')
        return nil unless action_type.nil? || action_type == 'GoTo'

        # Extract destination from /D
        d_val = @reader.dict_value(action_text, 'D')
        return nil unless d_val

        match = d_val.match(/(\d+)\s+\d+\s+R/)
        match ? match[1].to_i : nil
      end

      # Build chapters from outline entries by grouping consecutive pages.
      def build_chapters(outlines)
        if outlines.empty?
          return build_auto_chapters
        end

        chapters = []
        total = outlines.size

        outlines.each_with_index do |entry, idx|
          start_page = entry[:page_idx]
          next unless start_page

          # End page is the page before the next outline entry starts
          end_page = find_chapter_end_page(outlines, idx)

          report("Building chapter #{idx + 1}/#{total}...",
                 progress: 0.3 + 0.6 * (idx.to_f / [total, 1].max))

          raw_text = extract_pages_text(start_page, end_page)
          title = sanitize(entry[:title] || "Chapter #{chapters.size + 1}")

          chapters << Core::Models::Chapter.new(
            number: (chapters.size + 1).to_s,
            title: title,
            lines: nil,
            metadata: { format: :pdf, depth: entry[:depth], start_page: start_page, end_page: end_page },
            blocks: nil,
            raw_content: raw_text
          )
        end

        chapters = build_auto_chapters if chapters.empty?
        chapters
      end

      def find_chapter_end_page(outlines, current_idx)
        # Find the next outline entry with a valid page_idx
        ((current_idx + 1)...outlines.size).each do |i|
          next_page = outlines[i][:page_idx]
          return next_page - 1 if next_page && next_page > 0
        end
        # Last chapter goes to end of document
        @pages.size - 1
      end

      # Fallback: group pages into chapters of N pages each.
      def build_auto_chapters
        chapters = []
        total_pages = @pages.size
        chapter_num = 0

        (0...total_pages).step(PAGES_PER_AUTO_CHAPTER) do |start_page|
          chapter_num += 1
          end_page = [start_page + PAGES_PER_AUTO_CHAPTER - 1, total_pages - 1].min

          report("Building chapter #{chapter_num}...",
                 progress: 0.3 + 0.6 * (start_page.to_f / [total_pages, 1].max))

          raw_text = extract_pages_text(start_page, end_page)
          title = "Pages #{start_page + 1}-#{end_page + 1}"

          chapters << Core::Models::Chapter.new(
            number: chapter_num.to_s,
            title: title,
            lines: nil,
            metadata: { format: :pdf, start_page: start_page, end_page: end_page },
            blocks: nil,
            raw_content: raw_text
          )
        end

        chapters
      end

      def extract_pages_text(start_page, end_page)
        layout_lines = []
        plain_texts = []
        (start_page..end_page).each do |page_idx|
          next unless page_idx >= 0 && page_idx < @pages.size

          page_object = @pages[page_idx]
          lines = @extractor.respond_to?(:extract_page_layout) ? @extractor.extract_page_layout(page_object) : []
          if lines && !lines.empty?
            layout_lines.concat(lines.map { |line| normalize_layout_line(line) })
            layout_lines << { text: '', break: true }
          else
            text = @extractor.extract_page_text(page_object)
            plain_texts << text unless text.nil? || text.strip.empty?
          end
        end

        unless layout_lines.empty?
          payload = build_layout_payload(layout_lines)
          return payload unless payload.empty?
        end

        plain_texts.join("\n\n")
      end

      def normalize_layout_line(line)
        {
          text: line[:text] || line['text'],
          x: line[:x] || line['x'],
          italic: line[:italic] || line['italic'],
          italic_ratio: line[:italic_ratio] || line['italic_ratio'],
        }
      end

      def build_layout_payload(lines)
        compacted = lines.reverse.drop_while { |line| line[:break] || line['break'] }.reverse
        JSON.generate(
          {
            format: 'pdf-layout-v1',
            lines: compacted,
          }
        )
      rescue StandardError
        ''
      end

      def build_toc_entries(outlines, chapters)
        if outlines.empty?
          return chapters.each_with_index.map do |chapter, idx|
            Core::Models::TOCEntry.new(
              title: chapter.title,
              href: nil,
              level: 0,
              chapter_index: idx,
              navigable: true
            )
          end
        end

        outlines.each_with_index.map do |entry, idx|
          Core::Models::TOCEntry.new(
            title: sanitize(entry[:title] || "Chapter #{idx + 1}"),
            href: nil,
            level: entry[:depth] || 0,
            chapter_index: idx,
            navigable: true
          )
        end
      end

      def sanitize(text)
        Shoko::Shared::TextSanitizer.sanitize(
          text.to_s, preserve_newlines: false, preserve_tabs: false
        )
      rescue StandardError
        text.to_s
      end

      def fallback_title(path)
        fallback_title_from_path(path) { |text| sanitize(text) }
      end
    end
  end
end
