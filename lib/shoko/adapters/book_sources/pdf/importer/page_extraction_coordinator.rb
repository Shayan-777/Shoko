# frozen_string_literal: true

require 'json'

module Shoko
  module Adapters
    module BookSources
      module Pdf
        module Importer
          # Extracts chapter text using layout-first strategy with plain-text fallback.
          class PageExtractionCoordinator
            def initialize(pages:, extractor:)
              @pages = pages
              @extractor = extractor
            end

            def extract_text(start_page:, end_page:)
              layout_lines = []
              plain_texts = []

              each_page_object(start_page, end_page) do |page_object|
                append_page_content(page_object, layout_lines, plain_texts)
              end

              payload = layout_payload(layout_lines)
              return payload if payload

              plain_texts.join("\n\n")
            end

            private

            def each_page_object(start_page, end_page)
              (start_page..end_page).each do |page_idx|
                next unless page_idx >= 0 && page_idx < @pages.size

                yield(@pages[page_idx])
              end
            end

            def append_page_content(page_object, layout_lines, plain_texts)
              lines = safe_extract_layout(page_object)
              if lines&.any?
                append_layout_lines(lines, layout_lines)
              else
                append_plain_text(page_object, plain_texts)
              end
            end

            def safe_extract_layout(page_object)
              @extractor.extract_page_layout(page_object)
            rescue Shoko::Error
              empty_layout_lines
            end

            def append_layout_lines(lines, layout_lines)
              layout_lines.concat(lines.map { |line| normalize_layout_line(line) })
              layout_lines << { text: '', break: true }
            end

            def append_plain_text(page_object, plain_texts)
              text = @extractor.extract_page_text(page_object)
              plain_texts << text unless text.nil? || text.strip.empty?
            rescue Shoko::Error
              empty_text
            end

            def normalize_layout_line(line)
              {
                text: layout_value(line, :text),
                x: layout_value(line, :x),
                italic: layout_value(line, :italic),
                italic_ratio: layout_value(line, :italic_ratio),
              }
            end

            def layout_value(line, key)
              return nil unless line.is_a?(Hash)
              return line[key] if line.key?(key)

              line[key.to_s]
            end

            def layout_payload(lines)
              return nil if lines.empty?

              compacted = trim_trailing_breaks(lines)
              payload = JSON.generate(format: 'pdf-layout-v1', lines: compacted)
              payload.empty? ? nil : payload
            rescue Shoko::Error => e
              raise Shoko::MalformedBookInputError, "failed to build PDF layout payload: #{e.message}"
            end

            def trim_trailing_breaks(lines)
              lines.reverse.drop_while { |line| line[:break] || line['break'] }.reverse
            end

            def empty_layout_lines
              []
            end

            def empty_text
              +''
            end
          end
        end
      end
    end
  end
end
