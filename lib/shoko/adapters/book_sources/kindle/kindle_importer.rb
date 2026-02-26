# frozen_string_literal: true

require_relative '../../../shared/errors'
require_relative '../../../core/models/chapter'
require_relative '../../../core/models/toc_entry'
require_relative '../../../core/models/book_data'
require_relative '../../../shared/text_sanitizer'
require_relative '../../../core/book_formats/kindle/pdb_header_parser'
require_relative '../../../core/book_formats/kindle/mobi_header_parser'
require_relative '../../../core/book_formats/kindle/exth_parser'
require_relative '../../../core/book_formats/kindle/palmdoc_decompressor'
require_relative '../../../core/book_formats/kindle/kindle_metadata_extractor'
require_relative '../../../core/book_formats/kindle/metadata_parser'
require_relative '../../../core/book_formats/format_registry'

module Shoko
  module Adapters::BookSources::Kindle
    # Imports MOBI, AZW, and AZW3 (KF8) files into the same in-memory
    # {Core::Models::BookData} representation used by all formats,
    # so the entire downstream pipeline (cache, formatting, rendering) works
    # unchanged.
    #
    # All three Kindle formats share the PDB container, MOBI header,
    # PalmDOC compression, and HTML/XHTML content structure.
    class KindleImporter
      DEFAULT_LANGUAGE = 'en_US'
      FALLBACK_CHUNK_SIZE = 20_000 # bytes per auto-chapter when no markers found

      # Regex patterns for chapter boundary detection
      PAGEBREAK_TAG = /<mbp:pagebreak\s*\/?>/i
      PAGEBREAK_DIV = /<div[^>]*class="mbp_pagebreak"[^>]*>(?:<\/div>)?/i
      HEADING_PATTERN = /<h[1-3][^>]*>/i

      # Regex for extracting chapter titles from HTML fragments
      TITLE_FROM_HEADING = /<h[1-6][^>]*>(.*?)<\/h[1-6]>/im
      TITLE_FROM_LARGE_FONT = /<font\s+size="[4-9]"[^>]*>(.*?)<\/font>/im
      TITLE_FROM_CENTER_TEXT = /<p[^>]*align="center"[^>]*>(.*?)<\/p>/im
      TITLE_FROM_CLASS_HEADING = /class="[^"]*(?:chapter|heading|sgc-\d+|calibre_\d+)[^"]*"[^>]*>(.*?)<\//im
      TITLE_FROM_BOLD = /<(?:b|strong)>(.*?)<\/(?:b|strong)>/im

      def initialize(formatting_service: nil, extract_resources: false, progress_reporter: nil, instrumentation: nil)
        @formatting_service = formatting_service
        @extract_resources = !!extract_resources
        @progress_reporter = progress_reporter
        @instrumentation = instrumentation
      end

      # @param path [String] path to .mobi, .azw, or .azw3 file
      # @return [Core::Models::BookData]
      def import(path)
        @kindle_path = File.expand_path(path)
        raise Shoko::FileNotFoundError, path unless File.file?(@kindle_path)

        report('Reading Kindle file...', progress: 0.0)
        raw_data = instrument('kindle.read') { File.binread(@kindle_path) }

        report('Parsing headers...', progress: 0.05)
        @pdb = instrument('kindle.pdb') { Core::BookFormats::Kindle::PdbHeaderParser.new(raw_data) }
        validate_pdb_type

        record0 = @pdb.record_data(0)
        @mobi = instrument('kindle.mobi') { Core::BookFormats::Kindle::MobiHeaderParser.new(record0) }
        validate_no_drm

        report('Extracting metadata...', progress: 0.1)
        metadata = instrument('kindle.metadata') { extract_metadata(record0) }

        report('Decompressing text...', progress: 0.2)
        html = instrument('kindle.decompress') { decompress_text }

        report('Encoding text...', progress: 0.4)
        html = encode_text(html)

        report('Splitting chapters...', progress: 0.5)
        chapters = instrument('kindle.chapters') { split_into_chapters(html) }

        report('Building table of contents...', progress: 0.8)
        toc_entries = build_toc_entries(chapters)

        report('Finalizing...', progress: 0.9)
        Core::Models::BookData.new(
          title: metadata[:title] || fallback_title(@kindle_path),
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
          format_data: { format: detect_format, source_type: detect_format }
        )
      rescue Shoko::Error
        raise
      rescue StandardError => e
        raise Shoko::BookParseError.new(e.message, path)
      end

      private

      # ── Header Validation ──────────────────────────────────────────────

      def validate_pdb_type
        type = @pdb.type
        creator = @pdb.creator
        unless type == 'BOOK' && creator == 'MOBI'
          raise Shoko::BookParseError.new(
            "Not a Mobipocket file (type=#{type.inspect}, creator=#{creator.inspect})",
            @kindle_path
          )
        end
      end

      def validate_no_drm
        return unless @mobi.drm?

        raise Shoko::BookParseError.new(
          'DRM-protected files are not supported',
          @kindle_path
        )
      end

      # ── Metadata Extraction ────────────────────────────────────────────

      def extract_metadata(record0)
        exth = nil

        if @mobi.has_exth?
          exth_data = record0.byteslice(@mobi.exth_offset..)
          if exth_data && exth_data.bytesize >= 12
            exth = Core::BookFormats::Kindle::ExthParser.new(exth_data, encoding_name: @mobi.encoding_name)
          end
        end

        canonical = Core::BookFormats::Kindle::MetadataParser.parse(
          mobi: @mobi,
          exth: exth,
          fallback_title: nil
        )
        authors = Array(canonical[:authors]).map(&:to_s).reject(&:empty?)

        metadata = {
          title: canonical[:title],
          authors: authors,
          language: canonical[:language],
          year: canonical[:year],
        }
        metadata[:author_str] = authors.join('; ') unless authors.empty?
        metadata[:title] = nil if metadata[:title]&.empty?
        metadata.compact
      end

      # ── Text Decompression ─────────────────────────────────────────────

      def decompress_text
        text_parts = []
        text_record_count = @mobi.text_record_count
        extra_flags = @mobi.extra_data_flags

        text_record_count.times do |i|
          record_index = i + 1
          break if record_index >= @pdb.num_records

          if (i % 20).zero?
            progress = 0.2 + 0.2 * (i.to_f / [text_record_count, 1].max)
            report("Decompressing record #{i + 1}/#{text_record_count}...", progress: progress)
          end

          record_data = @pdb.record_data(record_index)

          # Strip trailing data entries before decompression
          record_data = Core::BookFormats::Kindle::PalmdocDecompressor.strip_trailing_data(
            record_data, extra_flags
          )

          if @mobi.palmdoc_compressed?
            text_parts << Core::BookFormats::Kindle::PalmdocDecompressor.decompress(record_data)
          elsif @mobi.uncompressed?
            text_parts << record_data
          else
            raise Shoko::BookParseError.new(
              "Unsupported compression type: #{@mobi.compression_type}",
              @kindle_path
            )
          end
        end

        text_parts.join
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

      # ── Chapter Splitting ──────────────────────────────────────────────

      def split_into_chapters(html)
        # Strategy 1: Split on <mbp:pagebreak/> tags (MOBI/AZW v6)
        chapters = split_by_pagebreak_tag(html)
        return chapters if chapters.length > 1

        # Strategy 2: Split on class="mbp_pagebreak" divs (AZW3/KF8)
        chapters = split_by_pagebreak_div(html)
        return chapters if chapters.length > 1

        # Strategy 3: Split on heading tags
        chapters = split_by_headings(html)
        return chapters if chapters.length > 1

        # Strategy 4: Fallback — single chapter or size-based splitting
        split_by_size(html)
      end

      def split_by_pagebreak_tag(html)
        sections = html.split(PAGEBREAK_TAG)
        return [] if sections.length <= 1

        build_chapters_from_sections(sections)
      end

      def split_by_pagebreak_div(html)
        sections = html.split(PAGEBREAK_DIV)
        return [] if sections.length <= 1

        build_chapters_from_sections(sections)
      end

      def split_by_headings(html)
        # Split before each <h1>, <h2>, or <h3> tag
        parts = html.split(/(?=<h[1-3][^>]*>)/i)
        return [] if parts.length <= 1

        build_chapters_from_sections(parts)
      end

      def split_by_size(html)
        if html.bytesize <= FALLBACK_CHUNK_SIZE * 2
          # Small enough for single chapter
          return [build_chapter(1, extract_title(html) || 'Chapter 1', html)]
        end

        chapters = []
        pos = 0
        while pos < html.length
          chunk_end = [pos + FALLBACK_CHUNK_SIZE, html.length].min
          # Try to break at a paragraph boundary
          if chunk_end < html.length
            para_break = paragraph_boundary_before(
              html, chunk_end,
              minimum: pos + FALLBACK_CHUNK_SIZE / 2
            )
            chunk_end = para_break if para_break
          end

          fragment = html[pos...chunk_end]
          chapters << build_chapter(
            chapters.length + 1,
            extract_title(fragment) || "Section #{chapters.length + 1}",
            fragment
          )
          pos = chunk_end
        end

        chapters
      end

      def paragraph_boundary_before(html, upper_bound, minimum:)
        match = nil
        html[0...upper_bound].scan(/<\/p\s*>/i) { match = Regexp.last_match }
        return nil unless match

        boundary = match.end(0)
        boundary > minimum ? boundary : nil
      end

      def build_chapters_from_sections(sections)
        chapters = []
        total = sections.length

        sections.each_with_index do |fragment, idx|
          # Skip empty or whitespace-only sections
          next if fragment.strip.empty?
          next if fragment.gsub(/<[^>]+>/, '').strip.empty? && fragment.length < 100

          progress = 0.5 + 0.3 * (idx.to_f / [total, 1].max)
          report("Building chapter #{chapters.length + 1}...", progress: progress)

          title = extract_title(fragment)
          title = normalize_chapter_title(title, chapters.length + 1)
          chapters << build_chapter(chapters.length + 1, title, fragment)
        end

        chapters
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

      # ── Title Extraction ───────────────────────────────────────────────

      def normalize_chapter_title(title, fallback_number)
        return "Chapter #{fallback_number}" if title.nil?

        # If the title is just a bare number, prefix with "Chapter"
        return "Chapter #{title}" if title.match?(/\A\d+\z/)

        # If the title is a Roman numeral, prefix with "Chapter"
        return "Chapter #{title}" if title.match?(/\A[IVXLCDM]+\.?\z/i)

        title
      end

      def extract_title(html_fragment)
        # Try multiple strategies for extracting chapter title,
        # preferring semantic headings over presentational markers.

        # Strategy 1: Heading tags (<h1>-<h6>) — most semantic
        title = extract_title_from_pattern(html_fragment, TITLE_FROM_HEADING)
        return title if title

        # Strategy 2: Large font text (common MOBI chapter title style)
        title = extract_title_from_pattern(html_fragment, TITLE_FROM_LARGE_FONT)
        return title if title

        # Strategy 3: Centered paragraph text
        title = extract_title_from_pattern(html_fragment, TITLE_FROM_CENTER_TEXT)
        return title if title

        # Strategy 4: Class-based headings (AZW3 patterns)
        title = extract_title_from_pattern(html_fragment, TITLE_FROM_CLASS_HEADING)
        return title if title

        # Strategy 5: Bold text (skip single-char drop caps)
        title = extract_title_from_pattern(html_fragment, TITLE_FROM_BOLD, min_length: 2)
        return title if title

        nil
      end

      def extract_title_from_pattern(html, pattern, min_length: 1)
        match = html.match(pattern)
        return nil unless match

        raw = match[1].gsub(/<[^>]+>/, '').strip
        return nil if raw.empty?
        return nil if raw.length < min_length
        return nil if raw.length > 200

        raw
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
        Shoko::Shared::TextSanitizer.sanitize(
          cleaned, preserve_newlines: false, preserve_tabs: false
        )
      rescue StandardError
        text.to_s
      end

      def fallback_title(path)
        basename = File.basename(path)
        %w[.mobi .azw3 .azw].each do |ext|
          basename = basename[0..-(ext.length + 1)] if basename.downcase.end_with?(ext)
        end
        sanitize(basename.tr('_', ' '))
      end

      def report(message, progress: nil)
        reporter = @progress_reporter
        return unless reporter
        return if message.nil? || message.to_s.strip.empty?

        if reporter.respond_to?(:call)
          reporter.call(message: message, progress: progress)
        elsif reporter.respond_to?(:update_status)
          reporter.update_status(message: message, progress: progress)
        end
      rescue StandardError
        nil
      end

      def instrument(label, &)
        if @instrumentation
          @instrumentation.measure(label, &)
        else
          yield
        end
      end
    end
  end
end
