# frozen_string_literal: true

require_relative '../../../shared/errors'
require_relative '../../../core/models/chapter'
require_relative '../../../core/models/toc_entry'
require_relative '../../../core/models/book_data'
require_relative '../../../adapters/book_sources/rtf/parser/rtf_parser'
require_relative '../../../adapters/book_sources/rtf/parser/rtf_metadata_extractor'
require_relative '../../../adapters/book_sources/rtf/parser/metadata_parser'
require_relative 'rtf_importer/chapter_partitioning'
require_relative 'rtf_importer/html_rendering'
require_relative '../../support/lifecycle_helpers'

module Shoko
  module Adapters
    module BookSources
      module Rtf
        # Main importer for RTF (.rtf) ebook files.
        #
        # Parses the RTF document, splits it into chapters based on heading
        # patterns or page breaks, converts each chapter to HTML for lazy
        # content parsing, and returns a BookData struct.
        class RtfImporter
          include Shoko::Adapters::Support::LifecycleHelpers
          include ChapterPartitioning
          include HtmlRendering

          DEFAULT_LANGUAGE = 'en_US'

          # Chapter heading detection patterns
          CHAPTER_HEADING = /\A\s*(?:CHAPTER|Chapter)\s+[IVXLCDM\d]+\.?\s*\z/
          VOLUME_HEADING  = /\A\s*(?:VOLUME|Volume|PART|Part|BOOK|Book)\s+[IVXLCDM\d]+\.?\s*\z/

          def initialize(formatting_service: nil, extract_resources: false,
                         progress_reporter: nil, instrumentation: nil)
            @formatting_service = formatting_service
            @extract_resources = extract_resources ? true : false
            @progress_reporter = progress_reporter
            @instrumentation = instrumentation
          end

          # @param path [String] path to .rtf file
          # @return [Core::Models::BookData]
          def import(path)
            @rtf_path = validated_rtf_path(path)
            doc = parsed_rtf_document
            metadata = instrumented_rtf_metadata(doc)
            chapters = build_chapters(instrumented_chapter_groups(doc))
            build_book_data(metadata, chapters)
          rescue Shoko::Error => e
            raise if e.is_a?(Shoko::FileNotFoundError)

            raise Shoko::BookParseError.new(e.message, path)
          end

          private

          def validated_rtf_path(path)
            expanded = File.expand_path(path)
            raise Shoko::FileNotFoundError, path unless File.file?(expanded)

            expanded
          end

          def parsed_rtf_document
            report('Reading RTF file...', progress: 0.0)
            raw = instrument('rtf.read') { File.binread(@rtf_path) }

            report('Parsing RTF document...', progress: 0.1)
            instrument('rtf.parse') { parse_rtf(raw) }
          end

          def instrumented_rtf_metadata(doc)
            report('Extracting metadata...', progress: 0.3)
            instrument('rtf.metadata') { extract_metadata(doc) }
          end

          def instrumented_chapter_groups(doc)
            report('Splitting chapters...', progress: 0.4)
            instrument('rtf.chapters') { split_into_chapters(doc) }
          end

          def build_book_data(metadata, chapters)
            report('Building table of contents...', progress: 0.8)
            toc_entries = build_toc_entries(chapters)
            report('Finalizing...', progress: 0.9)

            Core::Models::BookData.new(**book_data_attributes(metadata, chapters, toc_entries))
          end

          def book_data_attributes(metadata, chapters, toc_entries)
            {
              title: metadata[:title] || fallback_title,
              language: metadata[:language] || DEFAULT_LANGUAGE,
              authors: Array(metadata[:authors]).map(&:to_s),
              chapters: chapters,
              toc_entries: toc_entries,
              resources: {},
              metadata: metadata,
              format_data: { format: :rtf, source_type: :rtf },
            }
          end

          def parse_rtf(raw)
            content = raw.force_encoding('BINARY').encode('UTF-8', invalid: :replace, undef: :replace, replace: '')

            raise Shoko::BookParseError.new('Not a valid RTF file', @rtf_path) unless content.match?(/\A\s*\{\\rtf/)

            Adapters::BookSources::Rtf::RtfParser.new(content).parse
          end

          def extract_metadata(doc)
            canonical = Adapters::BookSources::Rtf::MetadataParser.parse(doc: doc, fallback_title: fallback_title)
            authors = Array(canonical[:authors]).map(&:to_s).reject(&:empty?)

            {
              title: canonical[:title],
              authors: authors,
              year: canonical[:year],
              language: canonical[:language],
              author_str: authors.empty? ? nil : authors.join('; '),
            }
          end

          def fallback_title
            fallback_title_from_path(@rtf_path, trim_parenthetical: true)
          end
        end
      end
    end
  end
end
