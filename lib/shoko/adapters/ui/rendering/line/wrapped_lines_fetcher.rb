# frozen_string_literal: true

require_relative '../../../../application/ports/outbound/formatting/display_line'

module Shoko
  module Adapters
    module Ui
      module Components
        module Reading
          # Fetches wrapped lines from the document using the formatting and wrapping services.
          #
          # Also applies the "image block offset snap" behavior so paging doesn't land in the
          # middle of a Kitty image placeholder block (which can cause disappearing images).
          class WrappedLinesFetcher
            def initialize(dependencies)
              @dependencies = dependencies
            end

            def fetch(document:, chapter_index:, col_width:, offset:, length:)
              chapter = document&.get_chapter(chapter_index)
              return [] unless chapter

              lines = service_lines(
                document: document,
                chapter: chapter,
                chapter_index: chapter_index,
                col_width: col_width,
                offset: offset,
                length: length
              )
              return lines unless lines.empty?

              fallback_lines(chapter, offset, length)
            end

            def fetch_with_offset(document:, chapter_index:, col_width:, offset:, length:)
              offset_i = offset.to_i
              lines = fetch(document: document,
                            chapter_index: chapter_index,
                            col_width: col_width,
                            offset: offset_i,
                            length: length)
              snapped = snap_offset_to_image_start(lines, offset_i)
              return [lines, offset_i] if snapped == offset_i

              [fetch(document: document,
                     chapter_index: chapter_index,
                     col_width: col_width,
                     offset: snapped,
                     length: length), snapped]
            end

            def snap_offset_to_image_start(lines, offset)
              offset_i = offset.to_i
              return offset_i if offset_i <= 0

              meta = image_block_metadata(lines)
              return offset_i unless meta

              idx = image_line_index(meta)
              return offset_i unless idx

              snapped_offset(offset_i, idx)
            rescue Shoko::Error
              offset.to_i
            end

            private

            def service_lines(document:, chapter:, chapter_index:, col_width:, offset:, length:)
              request = {
                document: document,
                chapter_index: chapter_index,
                col_width: col_width,
                offset: offset,
                length: length,
              }
              lines = formatting_lines(request)
              return lines unless lines.empty?

              wrapping_lines(request, chapter)
            end

            def formatting_lines(request)
              fetch_via_formatting_service(
                document: request.fetch(:document),
                chapter_index: request.fetch(:chapter_index),
                col_width: request.fetch(:col_width),
                offset: request.fetch(:offset),
                length: request.fetch(:length)
              )
            end

            def wrapping_lines(request, chapter)
              fetch_via_wrapping_service(
                document: request.fetch(:document),
                chapter: chapter,
                chapter_index: request.fetch(:chapter_index),
                col_width: request.fetch(:col_width),
                offset: request.fetch(:offset),
                length: request.fetch(:length)
              )
            end

            def fetch_via_formatting_service(document:, chapter_index:, col_width:, offset:, length:)
              formatting_service = @dependencies&.formatting_service
              return [] unless formatting_service

              config = @dependencies.config_reader

              Array(
                formatting_service.wrap_window(
                  document,
                  chapter_index,
                  col_width,
                  offset: offset,
                  length: length,
                  config: config,
                  lines_per_page: length
                )
              )
            end

            def fetch_via_wrapping_service(document:, chapter:, chapter_index:, col_width:, offset:, length:)
              wrapping = @dependencies&.wrapping_service
              return [] unless wrapping

              wrapping.wrap_window(
                plain_lines_for(document, chapter_index, chapter),
                chapter_index,
                col_width,
                offset,
                length,
                document: document
              ) || []
            end

            def fallback_lines(chapter, offset, length)
              lines = plain_lines_for(nil, nil, chapter)
              lines[offset, length] || []
            end

            # Source plain lines from the formatter (which now owns parsing)
            # instead of the deprecated `chapter.lines` back-write. Accepts a
            # nil document/chapter_index for the pure-fallback path where we
            # only have the chapter struct to fall back on.
            def plain_lines_for(document, chapter_index, chapter)
              formatting_service = @dependencies&.formatting_service
              if formatting_service && document && chapter_index
                lines = formatting_service.plain_lines_for(document, chapter_index)
                return Array(lines) unless lines.nil? || lines.empty?
              end
              Array(chapter&.lines)
            end

            def first_line_metadata(lines)
              first = Array(lines).first
              return nil unless first.is_a?(Shoko::Application::Ports::Outbound::Formatting::DisplayLine)

              meta = first.metadata
              meta.is_a?(Hash) ? meta : nil
            end

            def image_render_hash?(meta)
              return false unless meta.is_a?(Hash)

              render = meta[:image_render]
              render.is_a?(Hash)
            end

            def image_block_metadata(lines)
              meta = first_line_metadata(lines)
              return nil unless image_render_hash?(meta)
              return nil if image_render_line?(meta)

              meta
            end

            def image_render_line?(meta)
              value = meta[:image_render_line]
              value == true
            end

            def image_line_index(meta)
              meta[:image_line_index]&.to_i
            end

            def snapped_offset(offset, index)
              snapped = offset.to_i - index.to_i
              snapped.negative? ? 0 : snapped
            end
          end
        end
      end
    end
  end
end
