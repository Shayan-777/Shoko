# frozen_string_literal: true

require_relative '../../../shared/errors'
require_relative '../../../core/models/chapter'
require_relative '../../../core/models/toc_entry'
require_relative '../../../core/models/book_data'
require_relative '../../../adapters/book_sources/rtf/parser/rtf_parser'
require_relative '../../../adapters/book_sources/rtf/parser/rtf_metadata_extractor'
require_relative '../../../adapters/book_sources/rtf/parser/metadata_parser'
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

          def split_into_chapters(doc)
            paragraphs = Array(doc.paragraphs)
            page_break_groups = split_by_page_breaks(paragraphs)
            return page_break_groups if page_break_groups.length > 1

            heading_groups = split_by_headings(paragraphs)
            return heading_groups if heading_groups.length > 1

            [build_chapter_group(paragraphs)]
          end

          def split_by_page_breaks(paragraphs)
            groups = []
            current = []

            Array(paragraphs).each do |paragraph|
              append_page_break_group(groups, current) if paragraph.page_break_before && !current.empty?
              current << paragraph
            end

            append_page_break_group(groups, current)
            groups
          end

          def append_page_break_group(groups, paragraphs)
            return if paragraphs.empty?

            groups << build_chapter_group(paragraphs)
            paragraphs.clear
          end

          def split_by_headings(paragraphs)
            groups = []
            current = []
            heading = { title: nil, level: 0 }

            Array(paragraphs).each do |paragraph|
              heading_type = detect_heading(paragraph)
              if heading_type
                append_heading_group(groups, current, heading)
                current = [paragraph]
                heading = heading_state(paragraph, heading_type)
              else
                current << paragraph
              end
            end

            append_heading_group(groups, current, heading)
            groups
          end

          def append_heading_group(groups, paragraphs, heading)
            return if heading[:title].nil? && paragraphs.empty?

            groups << build_chapter_group(paragraphs, title: heading[:title], level: heading[:level])
          end

          def heading_state(paragraph, heading_type)
            {
              title: paragraph_text(paragraph),
              level: heading_type == :volume ? 0 : 1,
            }
          end

          def build_chapter_group(paragraphs, title: nil, level: 0)
            {
              title: title || extract_title(paragraphs),
              paragraphs: Array(paragraphs).dup,
              level: level,
            }
          end

          def detect_heading(paragraph)
            return nil unless centered_bold_paragraph?(paragraph)

            text = paragraph_text(paragraph)
            return :volume if text.match?(VOLUME_HEADING)
            return :chapter if text.match?(CHAPTER_HEADING)

            nil
          end

          def centered_bold_paragraph?(paragraph)
            runs = Array(paragraph.runs)
            runs.any? && paragraph.alignment == :center && runs.all?(&:bold)
          end

          def extract_title(paragraphs)
            Array(paragraphs).first(5).each do |paragraph|
              text = paragraph_text(paragraph)
              return text unless text.empty?
            end

            'Untitled'
          end

          def paragraph_text(paragraph)
            Array(paragraph.runs).map(&:text).join.strip
          end

          def build_chapters(chapter_groups)
            Array(chapter_groups).each_with_index.map do |group, index|
              Core::Models::Chapter.new(
                number: (index + 1).to_s,
                title: group[:title],
                lines: nil,
                metadata: { format: :rtf, level: group[:level] },
                blocks: nil,
                raw_content: paragraphs_to_html(group[:paragraphs])
              )
            end
          end

          def build_toc_entries(chapters)
            Array(chapters).each_with_index.map do |chapter, index|
              Core::Models::TOCEntry.new(
                title: chapter.title || "Chapter #{index + 1}",
                href: nil,
                level: chapter.metadata[:level] || 0,
                chapter_index: index,
                navigable: true
              )
            end
          end

          def paragraphs_to_html(paragraphs)
            html = +'<html><body>'
            Array(paragraphs).each { |paragraph| html << paragraph_to_html(paragraph) }
            html << '</body></html>'
          end

          def paragraph_to_html(paragraph)
            return '' unless paragraph_has_text?(paragraph)

            tag = paragraph_tag(paragraph)
            attrs = alignment_attr(paragraph.alignment)
            inner = Array(paragraph.runs).map { |run| run_to_html(run) }.join
            "<#{tag}#{attrs}>#{inner}</#{tag}>"
          end

          def paragraph_has_text?(paragraph)
            Array(paragraph.runs).any? && paragraph_text(paragraph).length.positive?
          end

          def paragraph_tag(paragraph)
            max_font_size = Array(paragraph.runs).map { |run| run.font_size || 24 }.max
            return 'h1' if max_font_size >= 48
            return 'h2' if max_font_size >= 36
            return 'h3' if max_font_size >= 28 && paragraph.alignment == :center

            'p'
          end

          def run_to_html(run)
            text = escape_html(run.text)
            return '' if text.empty?

            apply_run_wrappers(text, run)
          end

          def apply_run_wrappers(text, run)
            wrapped = text
            wrapped = "<sub>#{wrapped}</sub>" if run.subscript
            wrapped = "<sup>#{wrapped}</sup>" if run.superscript
            wrapped = "<s>#{wrapped}</s>" if run.strikethrough
            wrapped = "<u>#{wrapped}</u>" if run.underline
            wrapped = "<i>#{wrapped}</i>" if run.italic
            wrapped = "<b>#{wrapped}</b>" if run.bold
            wrapped
          end

          def alignment_attr(alignment)
            case alignment
            when :center
              ' style="text-align:center"'
            when :right
              ' style="text-align:right"'
            when :justify
              ' style="text-align:justify"'
            else
              ''
            end
          end

          def escape_html(text)
            text.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
          end
        end
      end
    end
  end
end
