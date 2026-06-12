# frozen_string_literal: true

require_relative '../../../shared/errors'
require_relative '../../../core/models/chapter'
require_relative '../../../core/models/toc_entry'
require_relative '../../../core/models/book_data'
require_relative '../../../shared/text_sanitizer'
require_relative '../../../adapters/book_sources/kindle/parser/pdb_header_parser'
require_relative '../../../adapters/book_sources/kindle/parser/mobi_header_parser'
require_relative '../../../adapters/book_sources/kindle/parser/exth_parser'
require_relative '../../../adapters/book_sources/kindle/parser/palmdoc_decompressor'
require_relative '../../../adapters/book_sources/kindle/parser/kindle_metadata_extractor'
require_relative '../../../adapters/book_sources/kindle/parser/metadata_parser'
require_relative '../../../adapters/book_sources/format_registry'
require_relative '../../support/lifecycle_helpers'

module Shoko
  module Adapters
    module BookSources
      module Kindle
        # Imports MOBI, AZW, and AZW3 (KF8) files into the same in-memory
        # {Core::Models::BookData} representation used by all formats,
        # so the entire downstream pipeline (cache, formatting, rendering) works
        # unchanged.
        #
        # All three Kindle formats share the PDB container, MOBI header,
        # PalmDOC compression, and HTML/XHTML content structure.
        class KindleImporter
          include Shoko::Adapters::Support::LifecycleHelpers

          DEFAULT_LANGUAGE = 'en_US'
          FALLBACK_CHUNK_SIZE = 20_000 # bytes per auto-chapter when no markers found

          # Regex patterns for chapter boundary detection
          PAGEBREAK_TAG = %r{<mbp:pagebreak\s*/?>}i
          PAGEBREAK_DIV = %r{<div[^>]*class="mbp_pagebreak"[^>]*>(?:</div>)?}i
          HEADING_PATTERN = /<h[1-3][^>]*>/i

          # Regex for extracting chapter titles from HTML fragments
          TITLE_FROM_HEADING = %r{<h[1-6][^>]*>(.*?)</h[1-6]>}im
          TITLE_FROM_LARGE_FONT = %r{<font\s+size="[4-9]"[^>]*>(.*?)</font>}im
          TITLE_FROM_CENTER_TEXT = %r{<p[^>]*align="center"[^>]*>(.*?)</p>}im
          TITLE_FROM_CLASS_HEADING = %r{class="[^"]*(?:chapter|heading|sgc-\d+|calibre_\d+)[^"]*"[^>]*>(.*?)</}im
          TITLE_FROM_BOLD = %r{<(?:b|strong)>(.*?)</(?:b|strong)>}im

          def initialize(formatting_service: nil, extract_resources: false, progress_reporter: nil,
                         instrumentation: nil)
            @formatting_service = formatting_service
            @extract_resources = extract_resources ? true : false
            @progress_reporter = progress_reporter
            @instrumentation = instrumentation
          end

          # @param path [String] path to .mobi, .azw, or .azw3 file
          # @return [Core::Models::BookData]
          def import(path)
            @kindle_path = validated_kindle_path(path)
            raw_data = read_kindle_data
            record0 = parse_headers(raw_data)
            metadata = instrumented_kindle_metadata(record0)
            html = encoded_kindle_html
            chapters = instrumented_kindle_chapters(html)
            finalize_book_data(metadata, chapters)
          rescue Shoko::Error => e
            raise if e.is_a?(Shoko::FileNotFoundError)

            raise Shoko::BookParseError.new(e.message, path)
          end

          private

          def validated_kindle_path(path)
            kindle_path = File.expand_path(path)
            raise Shoko::FileNotFoundError, path unless File.file?(kindle_path)

            kindle_path
          end

          def read_kindle_data
            report('Reading Kindle file...', progress: 0.0)
            instrument('kindle.read') { File.binread(@kindle_path) }
          end

          def parse_headers(raw_data)
            report('Parsing headers...', progress: 0.05)
            @pdb = instrument('kindle.pdb') { Adapters::BookSources::Kindle::PdbHeaderParser.new(raw_data) }
            validate_pdb_type

            record0 = @pdb.record_data(0)
            @mobi = instrument('kindle.mobi') { Adapters::BookSources::Kindle::MobiHeaderParser.new(record0) }
            validate_no_drm
            record0
          end

          def instrumented_kindle_metadata(record0)
            report('Extracting metadata...', progress: 0.1)
            instrument('kindle.metadata') { extract_metadata(record0) }
          end

          def encoded_kindle_html
            report('Decompressing text...', progress: 0.2)
            html = instrument('kindle.decompress') { decompress_text }
            report('Encoding text...', progress: 0.4)
            encode_text(html)
          end

          def instrumented_kindle_chapters(html)
            report('Splitting chapters...', progress: 0.5)
            instrument('kindle.chapters') { split_into_chapters(html) }
          end

          def finalize_book_data(metadata, chapters)
            report('Building table of contents...', progress: 0.8)
            toc_entries = build_toc_entries(chapters)
            report('Finalizing...', progress: 0.9)
            kindle_book_data(metadata, chapters, toc_entries)
          end

          def kindle_book_data(metadata, chapters, toc_entries)
            Core::Models::BookData.new(
              title: metadata[:title] || fallback_title(@kindle_path),
              language: metadata[:language] || DEFAULT_LANGUAGE,
              authors: Array(metadata[:authors]).map(&:to_s),
              chapters: chapters,
              toc_entries: toc_entries,
              resources: {},
              metadata: metadata,
              format_data: { format: detect_format, source_type: detect_format }
            )
          end

          # ── Header Validation ──────────────────────────────────────────────

          def validate_pdb_type
            type = @pdb.type
            creator = @pdb.creator
            return if type == 'BOOK' && creator == 'MOBI'

            raise Shoko::BookParseError.new(
              "Not a Mobipocket file (type=#{type.inspect}, creator=#{creator.inspect})",
              @kindle_path
            )
          end

          def validate_no_drm
            return unless @mobi.drm?

            raise Shoko::BookParseError.new('DRM-protected files are not supported', @kindle_path)
          end

          def encode_text(raw_html)
            encoding = @mobi.encoding_name
            raw_html.force_encoding(encoding)

            if encoding != 'UTF-8'
              raw_html.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
            elsif !raw_html.valid_encoding?
              raw_html.encode('UTF-8', 'UTF-8', invalid: :replace, undef: :replace, replace: '')
            else
              raw_html
            end
          end

          # ── TOC Building ───────────────────────────────────────────────────

          def build_toc_entries(chapters)
            chapters.each_with_index.map do |chapter, idx|
              Core::Models::TOCEntry.new(
                title: chapter.title || "Chapter #{idx + 1}",
                href: nil,
                level: 0,
                chapter_index: idx,
                navigable: true
              )
            end
          end

          # ── Helpers ────────────────────────────────────────────────────────

          def detect_format
            ext = File.extname(@kindle_path).downcase
            case ext
            when '.mobi' then :mobi
            when '.azw3' then :azw3
            when '.azw' then :azw
            else :kindle
            end
          end

          def sanitize(text)
            cleaned = text.to_s
            # Decode HTML entities
            cleaned = cleaned.gsub('&amp;', '&').gsub('&lt;', '<').gsub('&gt;', '>')
                             .gsub('&quot;', '"').gsub('&#39;', "'").gsub('&apos;', "'")
            Shoko::Shared::TextSanitizer.sanitize(cleaned, preserve_newlines: false, preserve_tabs: false)
          rescue Shoko::Error
            text.to_s
          end

          def fallback_title(path)
            fallback_title_from_path(path, strip_suffixes: %w[.mobi .azw3 .azw]) { |text| sanitize(text) }
          end

          # ── Metadata Extraction ────────────────────────────────────────────

          def extract_metadata(record0)
            canonical = Adapters::BookSources::Kindle::MetadataParser.parse(
              mobi: @mobi,
              exth: extract_exth(record0),
              fallback_title: nil
            )
            build_metadata(canonical)
          end

          def extract_exth(record0)
            return nil unless @mobi.exth?

            exth_data = record0.byteslice(@mobi.exth_offset..)
            return nil unless exth_data && exth_data.bytesize >= 12

            Adapters::BookSources::Kindle::ExthParser.new(exth_data, encoding_name: @mobi.encoding_name)
          end

          def build_metadata(canonical)
            authors = Array(canonical[:authors]).map(&:to_s).reject(&:empty?)
            title = canonical[:title].to_s
            title = nil if title.empty?

            metadata = { title: title, authors: authors, language: canonical[:language], year: canonical[:year] }
            metadata[:author_str] = authors.join('; ') unless authors.empty?
            metadata.compact
          end

          # ── Decompression & Chapter Splitting ──────────────────────────────

          def decompress_text
            record_indices.each_with_object([]) do |record_index, text_parts|
              report_record_progress(record_index)
              text_parts << decompressed_record(record_index)
            end.join
          end

          def record_indices
            count = @mobi.text_record_count
            count.times.filter_map do |index|
              record_index = index + 1
              record_index < @pdb.num_records ? record_index : nil
            end
          end

          def report_record_progress(record_index)
            index = record_index - 1
            return unless (index % 20).zero?

            count = @mobi.text_record_count
            progress = 0.2 + (0.2 * (index.to_f / [count, 1].max))
            report("Decompressing record #{record_index}/#{count}...", progress: progress)
          end

          def decompressed_record(record_index)
            record_data = @pdb.record_data(record_index)
            stripped = Adapters::BookSources::Kindle::PalmdocDecompressor.strip_trailing_data(
              record_data,
              @mobi.extra_data_flags
            )
            return Adapters::BookSources::Kindle::PalmdocDecompressor.decompress(stripped) if @mobi.palmdoc_compressed?
            return stripped if @mobi.uncompressed?

            raise Shoko::BookParseError.new("Unsupported compression type: #{@mobi.compression_type}", @kindle_path)
          end

          def split_into_chapters(html)
            [
              method(:split_by_pagebreak_tag),
              method(:split_by_pagebreak_div),
              method(:split_by_headings),
            ].each do |strategy|
              chapters = strategy.call(html)
              return chapters if chapters.length > 1
            end

            split_by_size(html)
          end

          def split_by_pagebreak_tag(html)
            split_sections(html, PAGEBREAK_TAG)
          end

          def split_by_pagebreak_div(html)
            split_sections(html, PAGEBREAK_DIV)
          end

          def split_by_headings(html)
            parts = html.split(/(?=<h[1-3][^>]*>)/i)
            parts.length > 1 ? build_chapters_from_sections(parts) : []
          end

          def split_sections(html, pattern)
            sections = html.split(pattern)
            sections.length > 1 ? build_chapters_from_sections(sections) : []
          end

          def split_by_size(html)
            return [single_chapter(html)] if html.bytesize <= FALLBACK_CHUNK_SIZE * 2

            chapters = []
            position = 0
            while position < html.length
              chunk_end = bounded_chunk_end(html, position)
              fragment = html[position...chunk_end]
              chapters << chapter_from_fragment(fragment, chapters.length + 1)
              position = chunk_end
            end
            chapters
          end

          def single_chapter(html)
            build_chapter(1, extract_title(html) || 'Chapter 1', html)
          end

          def bounded_chunk_end(html, position)
            chunk_end = [position + FALLBACK_CHUNK_SIZE, html.length].min
            return chunk_end unless chunk_end < html.length

            boundary = paragraph_boundary_before(html, chunk_end, minimum: position + (FALLBACK_CHUNK_SIZE / 2))
            boundary || chunk_end
          end

          def chapter_from_fragment(fragment, number)
            title = extract_title(fragment) || "Section #{number}"
            build_chapter(number, title, fragment)
          end

          def paragraph_boundary_before(html, upper_bound, minimum:)
            match = nil
            html[0...upper_bound].scan(%r{</p\s*>}i) { match = Regexp.last_match }
            return nil unless match

            boundary = match.end(0)
            boundary > minimum ? boundary : nil
          end

          def build_chapters_from_sections(sections)
            total = sections.length
            sections.each_with_index.with_object([]) do |(fragment, index), chapters|
              next if ignorable_fragment?(fragment)

              report(
                "Building chapter #{chapters.length + 1}...",
                progress: 0.5 + (0.3 * (index.to_f / [total, 1].max))
              )
              chapters << build_chapter_from_section(fragment, chapters.length + 1)
            end
          end

          def ignorable_fragment?(fragment)
            return true if fragment.strip.empty?

            fragment.gsub(/<[^>]+>/, '').strip.empty? && fragment.length < 100
          end

          def build_chapter_from_section(fragment, number)
            title = extract_title(fragment)
            title = normalize_chapter_title(title, number)
            build_chapter(number, title, fragment)
          end

          def build_chapter(number, title, raw_content)
            Core::Models::Chapter.new(
              number: number.to_s,
              title: sanitize(title),
              lines: nil,
              metadata: { format: detect_format },
              blocks: nil,
              raw_content: raw_content
            )
          end

          def normalize_chapter_title(title, fallback_number)
            return "Chapter #{fallback_number}" if title.nil?
            return "Chapter #{title}" if title.match?(/\A\d+\z/)
            return "Chapter #{title}" if title.match?(/\A[IVXLCDM]+\.?\z/i)

            title
          end

          def extract_title(html_fragment)
            [
              [TITLE_FROM_HEADING, 1],
              [TITLE_FROM_LARGE_FONT, 1],
              [TITLE_FROM_CENTER_TEXT, 1],
              [TITLE_FROM_CLASS_HEADING, 1],
              [TITLE_FROM_BOLD, 2],
            ].each do |pattern, min_length|
              title = extract_title_from_pattern(html_fragment, pattern, min_length: min_length)
              return title if title
            end

            nil
          end

          def extract_title_from_pattern(html, pattern, min_length: 1)
            match = html.match(pattern)
            return nil unless match

            raw = match[1].gsub(/<[^>]+>/, '').strip
            return nil if raw.empty? || raw.length < min_length || raw.length > 200

            raw
          end
        end
      end
    end
  end
end
