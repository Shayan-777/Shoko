# frozen_string_literal: true

require_relative '../../pagination'
require_relative '../../config_bridge'

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
          # Uses hexagonal ports for reading state - no direct state_store access.
          class PageHydrator
            def initialize(dependencies:, text_wrapper:, metrics_calculator:,
                           config_reader:, ui_state_reader:)
              @dependencies = dependencies
              @text_wrapper = text_wrapper
              @metrics_calculator = metrics_calculator
              @config_reader = config_reader
              @ui_state_reader = ui_state_reader
              @config_bridge = Services::ConfigBridge.new(config_reader)
            end

            def hydrate(page, doc, prefer_formatting: true)
              return page unless doc

              col_width = col_width_for
              offset, length = window_for(page)
              chapter_index = page[:chapter_index].to_i
              raw_lines = chapter_lines(doc, chapter_index, fallback: page[:lines])

              lines = hydrated_lines(doc, raw_lines, chapter_index, col_width,
                                     offset: offset,
                                     length: length,
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

            def wrapped_window(lines, chapter_index, col_width, offset:, length:)
              wrapper = resolve_wrapping_service
              if wrapper
                wrapped = wrapper.wrap_window(lines, chapter_index, col_width, offset, length)
                return fallback_slice(lines, col_width, offset, length) if wrapped.nil? || wrapped.empty?

                wrapped
              else
                fallback_slice(lines, col_width, offset, length)
              end
            end

            def formatted_window(doc, chapter_index, col_width, offset:, length:)
              formatting = resolve_formatting_service
              return nil unless formatting

              lines = formatting.wrap_window(
                doc,
                chapter_index,
                col_width,
                offset: offset,
                length: length,
                config: @config_bridge,
                lines_per_page: safe_lines_per_page(length)
              )
              return nil unless lines && !lines.empty?

              lines
            rescue StandardError
              nil
            end

            def safe_lines_per_page(fallback)
              lines = @metrics_calculator&.lines_per_page
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
              return nil unless @dependencies.respond_to?(:resolve)

              @dependencies.resolve(:wrapping_service)
            rescue StandardError
              nil
            end

            def resolve_formatting_service
              return nil unless @dependencies.respond_to?(:resolve)

              @dependencies.resolve(:formatting_service)
            rescue StandardError
              nil
            end

            def hydrated_lines(doc, raw_lines, chapter_index, col_width, offset:, length:, prefer_formatting:)
              if prefer_formatting
                formatted_window(doc, chapter_index, col_width, offset: offset, length: length) ||
                  wrapped_window(raw_lines, chapter_index, col_width, offset: offset, length: length)
              else
                wrapped_window(raw_lines, chapter_index, col_width, offset: offset, length: length)
              end
            end

            def col_width_for
              width = @ui_state_reader.terminal_width
              height = @ui_state_reader.terminal_height
              col_width, = @metrics_calculator.layout(width, height)
              col_width
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
