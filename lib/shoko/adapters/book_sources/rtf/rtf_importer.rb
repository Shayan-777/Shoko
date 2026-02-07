# frozen_string_literal: true

require_relative '../../../shared/errors'
require_relative '../../../core/models/chapter'
require_relative '../../../core/models/toc_entry'
require_relative '../../../core/models/book_data'
require_relative '../../../core/book_formats/rtf/rtf_parser'
require_relative '../../../core/book_formats/rtf/rtf_metadata_extractor'

module Shoko
  module Adapters::BookSources::Rtf
    # Main importer for RTF (.rtf) ebook files.
    #
    # Parses the RTF document, splits it into chapters based on heading
    # patterns or page breaks, converts each chapter to HTML for lazy
    # content parsing, and returns a BookData struct.
    class RtfImporter
      DEFAULT_LANGUAGE = 'en_US'

      # Chapter heading detection patterns
      CHAPTER_HEADING = /\A\s*(?:CHAPTER|Chapter)\s+[IVXLCDM\d]+\.?\s*\z/
      VOLUME_HEADING  = /\A\s*(?:VOLUME|Volume|PART|Part|BOOK|Book)\s+[IVXLCDM\d]+\.?\s*\z/

      def initialize(formatting_service: nil, extract_resources: false,
                     progress_reporter: nil, instrumentation: nil)
        @formatting_service = formatting_service
        @extract_resources = !!extract_resources
        @progress_reporter = progress_reporter
        @instrumentation = instrumentation
      end

      # @param path [String] path to .rtf file
      # @return [Core::Models::BookData]
      def import(path)
        @rtf_path = File.expand_path(path)
        raise Shoko::FileNotFoundError, path unless File.file?(@rtf_path)

        report('Reading RTF file...', progress: 0.0)
        raw = instrument('rtf.read') { File.binread(@rtf_path) }

        report('Parsing RTF document...', progress: 0.1)
        doc = instrument('rtf.parse') { parse_rtf(raw) }

        report('Extracting metadata...', progress: 0.3)
        metadata = instrument('rtf.metadata') { extract_metadata(doc) }

        report('Splitting chapters...', progress: 0.4)
        chapter_groups = instrument('rtf.chapters') { split_into_chapters(doc) }

        report('Building content...', progress: 0.6)
        chapters = build_chapters(chapter_groups)

        report('Building table of contents...', progress: 0.8)
        toc_entries = build_toc_entries(chapters)

        report('Finalizing...', progress: 0.9)
        Core::Models::BookData.new(
          title: metadata[:title] || fallback_title,
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
          format_data: { format: :rtf, source_type: :rtf }
        )
      rescue Shoko::Error
        raise
      rescue StandardError => e
        raise Shoko::BookParseError.new(e.message, path)
      end

      private

      def parse_rtf(raw)
        content = raw.force_encoding('BINARY').encode('UTF-8',
          invalid: :replace, undef: :replace, replace: '')

        unless content.match?(/\A\s*\{\\rtf/)
          raise Shoko::BookParseError.new('Not a valid RTF file', @rtf_path)
        end

        Core::BookFormats::Rtf::RtfParser.new(content).parse
      end

      def extract_metadata(doc)
        info = doc.info
        metadata = { title: nil, authors: [], year: nil, language: nil }

        info_unreliable = false
        if info
          raw_title = info.title.to_s.strip
          raw_author = info.author.to_s.strip

          if invalid_title?(raw_title)
            info_unreliable = true
          else
            metadata[:title] = raw_title
          end

          unless raw_author.empty? || info_unreliable
            metadata[:authors] = [raw_author]
          end

          if info.creatim
            year_match = info.creatim.to_s.match(/(\d{4})/)
            metadata[:year] = year_match[1] if year_match
          end
        end

        # Content fallback for title/author
        if metadata[:title].nil? || metadata[:authors].empty?
          content_meta = extract_from_content(doc)
          metadata[:title] ||= content_meta[:title]
          metadata[:authors] = content_meta[:authors] if metadata[:authors].empty?
        end

        metadata[:title] ||= fallback_title
        metadata[:author_str] = metadata[:authors].join('; ') unless metadata[:authors].empty?
        metadata
      end

      def invalid_title?(title)
        return true if title.empty?
        return true if title.length < 3
        return true if title.start_with?('[')
        return true if title.match?(/\A(Version|Draft|Document|Untitled)/i)

        false
      end

      def extract_from_content(doc)
        result = { title: nil, authors: [] }
        paragraphs = doc.paragraphs
        return result if paragraphs.empty?

        candidates = []
        paragraphs.first(30).each do |para|
          next if para.runs.empty?
          next unless para.alignment == :center

          text = para.runs.map(&:text).join.strip
          next if text.empty?
          next if text.length < 2

          max_fs = para.runs.map { |r| r.font_size || 24 }.max
          all_bold = para.runs.all?(&:bold)

          candidates << { text: text, font_size: max_fs, bold: all_bold }
        end

        return result if candidates.empty?

        sorted = candidates.sort_by { |c| [-c[:font_size], -c[:text].length] }
        result[:title] = sorted[0][:text] if sorted.length >= 1

        sorted.each do |c|
          next if c[:text] == result[:title]
          next unless c[:bold]
          next if c[:text].match?(/\A\[/)
          next if c[:text].match?(/\A\(\d{4}/)

          result[:authors] = [c[:text]]
          break
        end

        result
      end

      def fallback_title
        basename = File.basename(@rtf_path, File.extname(@rtf_path))
        if (m = basename.match(/\A(.+?)\s*\(.*\)\s*\z/))
          m[1].strip
        else
          basename.tr('_', ' ').strip
        end
      end

      # Split paragraphs into chapter groups.
      # Returns Array of { title:, paragraphs:, level: }
      def split_into_chapters(doc)
        paragraphs = doc.paragraphs

        # Strategy 1: Page breaks
        groups = split_by_page_breaks(paragraphs)
        return groups if groups.length > 1

        # Strategy 2: Chapter/volume headings
        groups = split_by_headings(paragraphs)
        return groups if groups.length > 1

        # Strategy 3: Single chapter fallback
        [{ title: 'Full Text', paragraphs: paragraphs, level: 0 }]
      end

      def split_by_page_breaks(paragraphs)
        groups = []
        current = []

        paragraphs.each do |para|
          if para.page_break_before && !current.empty?
            groups << { title: extract_title(current), paragraphs: current, level: 0 }
            current = []
          end
          current << para
        end

        groups << { title: extract_title(current), paragraphs: current, level: 0 } unless current.empty?
        groups
      end

      def split_by_headings(paragraphs)
        groups = []
        current = []
        current_title = nil
        current_level = 0

        paragraphs.each do |para|
          heading_type = detect_heading(para)

          if heading_type
            # Save previous group
            if current_title || !current.empty?
              title = current_title || extract_title(current)
              groups << { title: title, paragraphs: current, level: current_level }
            end

            text = para.runs.map(&:text).join.strip
            current = [para]
            current_title = text
            current_level = heading_type == :volume ? 0 : 1
          else
            current << para
          end
        end

        # Save last group
        if current_title || !current.empty?
          title = current_title || extract_title(current)
          groups << { title: title, paragraphs: current, level: current_level }
        end

        groups
      end

      def detect_heading(para)
        return nil if para.runs.empty?
        return nil unless para.alignment == :center
        return nil unless para.runs.all?(&:bold)

        text = para.runs.map(&:text).join.strip
        return nil if text.empty?

        if text.match?(VOLUME_HEADING)
          :volume
        elsif text.match?(CHAPTER_HEADING)
          :chapter
        end
      end

      def extract_title(paragraphs)
        return 'Untitled' if paragraphs.empty?

        # Look for first non-empty text
        paragraphs.first(5).each do |para|
          text = para.runs.map(&:text).join.strip
          return text unless text.empty?
        end

        'Untitled'
      end

      def build_chapters(chapter_groups)
        chapter_groups.each_with_index.map do |group, idx|
          html = paragraphs_to_html(group[:paragraphs])

          Core::Models::Chapter.new(
            number: (idx + 1).to_s,
            title: group[:title],
            lines: nil,
            metadata: { format: :rtf, level: group[:level] },
            blocks: nil,
            raw_content: html
          )
        end
      end

      def build_toc_entries(chapters)
        chapters.each_with_index.map do |chapter, idx|
          level = chapter.metadata[:level] || 0

          Core::Models::TOCEntry.new(
            title: chapter.title || "Chapter #{idx + 1}",
            href: nil,
            level: level,
            chapter_index: idx,
            navigable: true
          )
        end
      end

      # Convert parsed paragraphs to an HTML fragment
      def paragraphs_to_html(paras)
        html = +'<html><body>'
        paras.each do |para|
          html << paragraph_to_html(para)
        end
        html << '</body></html>'
        html
      end

      def paragraph_to_html(para)
        return '' if para.runs.empty?

        combined_text = para.runs.map(&:text).join.strip
        return '' if combined_text.empty?

        # Determine HTML tag based on font size
        max_fs = para.runs.map { |r| r.font_size || 24 }.max
        tag = if max_fs >= 48
                'h1'
              elsif max_fs >= 36
                'h2'
              elsif max_fs >= 28 && para.alignment == :center
                'h3'
              else
                'p'
              end

        attrs = alignment_attr(para.alignment)
        inner = para.runs.map { |run| run_to_html(run) }.join

        "<#{tag}#{attrs}>#{inner}</#{tag}>"
      end

      def run_to_html(run)
        text = escape_html(run.text)
        return '' if text.empty?

        text = "<sub>#{text}</sub>" if run.subscript
        text = "<sup>#{text}</sup>" if run.superscript
        text = "<s>#{text}</s>" if run.strikethrough
        text = "<u>#{text}</u>" if run.underline
        text = "<i>#{text}</i>" if run.italic
        text = "<b>#{text}</b>" if run.bold
        text
      end

      def alignment_attr(alignment)
        case alignment
        when :center  then ' style="text-align:center"'
        when :right   then ' style="text-align:right"'
        when :justify then ' style="text-align:justify"'
        else ''
        end
      end

      def escape_html(text)
        text.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
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
