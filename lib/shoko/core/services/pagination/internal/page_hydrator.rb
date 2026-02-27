# frozen_string_literal: true

require_relative '../../pagination'
require_relative '../../../ports/outbound/line_wrapper'
require_relative '../../../ports/outbound/chapter_formatter'

module Shoko
  module Core
    module Services
      module Pagination
        module Internal
          # Lazily hydrates cached page entries with rendered lines and chapter metadata.
          # When pagination data is loaded from disk we only have start/end line offsets.
          # The hydrator looks up the chapter, wraps text using the configured wrapper,
          # and returns an enriched page hash that callers can cache back into the
          # service-level page map.
          # Uses explicit layout dimensions passed by callers.
          class PageHydrator
            def initialize(text_wrapper:, metrics_calculator:,
                           config_reader:,
                           line_wrapper: nil, chapter_formatter: nil)
              @text_wrapper = text_wrapper
              @metrics_calculator = metrics_calculator
              @config_reader = config_reader
              @line_wrapper = line_wrapper
              @chapter_formatter = chapter_formatter
            end

            def hydrate(page, doc, width:, height:, sidebar_visible:, prefer_formatting: true)
              return page unless doc

              col_width, lines_per_page = layout_for(width, height, sidebar_visible: sidebar_visible)
              offset, length = window_for(page)
              chapter_index = page[:chapter_index].to_i
              raw_lines = chapter_lines(doc, chapter_index, fallback: page[:lines])

              lines = hydrated_lines(doc, raw_lines, chapter_index, col_width,
                                     offset: offset,
                                     length: length,
                                     lines_per_page: lines_per_page,
                                     prefer_formatting: prefer_formatting)
              page.merge(lines: lines)
            end

            private

            def chapter_lines(doc, chapter_index, fallback: nil)
              chapter = doc.get_chapter(chapter_index)
              chapter&.lines || Array(fallback)
            rescue StandardError
              Array(fallback)
            end

            def wrapped_window(document, lines, chapter_index, col_width, offset:, length:)
              wrapper = resolve_wrapping_service
              if wrapper
                wrapped = wrapper.wrap_window(lines, chapter_index, col_width, offset, length, document: document)
                return fallback_slice(lines, col_width, offset, length) if wrapped.nil? || wrapped.empty?

                wrapped
              else
                fallback_slice(lines, col_width, offset, length)
              end
            end

            def formatted_window(doc, chapter_index, col_width, offset:, length:, lines_per_page:)
              formatting = resolve_formatting_service
              return nil unless formatting

              lines = formatting.wrap_window(
                doc,
                chapter_index,
                col_width,
                offset: offset,
                length: length,
                config: @config_reader,
                lines_per_page: safe_lines_per_page(lines_per_page, length)
              )
              return nil unless lines && !lines.empty?

              lines
            rescue StandardError
              nil
            end

            def safe_lines_per_page(value, fallback)
              lines = value
              lines = nil if lines.to_i <= 0
              lines || fallback.to_i
            rescue StandardError
              fallback.to_i
            end

            def fallback_slice(lines, col_width, offset, length)
              wrapped = @text_wrapper.wrap_chapter_lines(lines, col_width)
              wrapped[offset, length] || []
            end

            def resolve_wrapping_service
              @line_wrapper
            end

            def resolve_formatting_service
              @chapter_formatter
            end

            def hydrated_lines(doc, raw_lines, chapter_index, col_width, offset:, length:, lines_per_page:, prefer_formatting:)
              if prefer_formatting
                formatted_window(doc, chapter_index, col_width, offset: offset, length: length,
                                                                lines_per_page: lines_per_page) ||
                  wrapped_window(doc, raw_lines, chapter_index, col_width, offset: offset, length: length)
              else
                wrapped_window(doc, raw_lines, chapter_index, col_width, offset: offset, length: length)
              end
            end

            def layout_for(width, height, sidebar_visible:)
              col_width, content_height = @metrics_calculator.layout(
                width,
                height,
                sidebar_visible: sidebar_visible
              )
              lines_per_page = @metrics_calculator.lines_per_page_for(content_height)
              [col_width, lines_per_page]
            rescue StandardError
              [80, 24]
            end

            def window_for(page)
              offset = page[:start_line].to_i
              end_line = page[:end_line].to_i
              length = (end_line - offset + 1)
              [offset, length]
            end
          end
        end
      end
    end
  end
end
