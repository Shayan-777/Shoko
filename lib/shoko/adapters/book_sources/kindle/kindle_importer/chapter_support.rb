# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Kindle
        class KindleImporter
          # Decompression, chapter splitting, and chapter title extraction helpers.
          module ChapterSupport
            private

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
              if @mobi.palmdoc_compressed?
                return Adapters::BookSources::Kindle::PalmdocDecompressor.decompress(stripped)
              end
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
end
