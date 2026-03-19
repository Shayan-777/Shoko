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
require_relative 'kindle_importer/metadata_support'
require_relative 'kindle_importer/chapter_support'
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
          include MetadataSupport
          include ChapterSupport

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
              opf_path: nil,
              spine: [],
              chapter_hrefs: [],
              resources: {},
              metadata: metadata,
              container_path: nil,
              container_xml: nil,
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

            raise Shoko::BookParseError.new(
              'DRM-protected files are not supported',
              @kindle_path
            )
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
            Shoko::Shared::TextSanitizer.sanitize(
              cleaned, preserve_newlines: false, preserve_tabs: false
            )
          rescue Shoko::Error
            text.to_s
          end

          def fallback_title(path)
            fallback_title_from_path(path, strip_suffixes: %w[.mobi .azw3 .azw]) { |text| sanitize(text) }
          end
        end
      end
    end
  end
end
