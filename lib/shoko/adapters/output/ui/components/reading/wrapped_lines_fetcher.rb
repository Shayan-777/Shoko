# frozen_string_literal: true

module Shoko
  module Adapters::Output::Ui::Components
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

          lines = fetch_via_formatting_service(document: document, chapter_index: chapter_index, col_width: col_width,
                                               offset: offset, length: length)
          return lines unless lines.empty?

          lines = fetch_via_wrapping_service(document: document, chapter: chapter, chapter_index: chapter_index,
                                             col_width: col_width,
                                             offset: offset, length: length)
          return lines unless lines.empty?

          fallback_lines(chapter, offset, length)
        end

        def fetch_with_offset(document:, chapter_index:, col_width:, offset:, length:)
          offset_i = offset.to_i
          lines = fetch(document: document, chapter_index: chapter_index, col_width: col_width, offset: offset_i,
                        length: length)
          snapped = snap_offset_to_image_start(lines, offset_i)
          return [lines, offset_i] if snapped == offset_i

          [fetch(document: document, chapter_index: chapter_index, col_width: col_width, offset: snapped,
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
        rescue StandardError
          offset.to_i
        end

        private

        def fetch_via_formatting_service(document:, chapter_index:, col_width:, offset:, length:)
          formatting_service = @dependencies&.formatting_service
          return [] unless formatting_service
          config = @dependencies.global_state

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
        rescue StandardError
          []
        end

        def fetch_via_wrapping_service(document:, chapter:, chapter_index:, col_width:, offset:, length:)
          wrapping = @dependencies&.wrapping_service
          return [] unless wrapping
          wrapping.wrap_window(
            chapter.lines || [],
            chapter_index,
            col_width,
            offset,
            length,
            document: document
          ) || []
        rescue StandardError
          []
        end

        def fallback_lines(chapter, offset, length)
          (chapter.lines || [])[offset, length] || []
        rescue StandardError
          []
        end

        def first_line_metadata(lines)
          first = Array(lines).first
          return nil unless first.respond_to?(:metadata)

          meta = first.metadata
          meta.is_a?(Hash) ? meta : nil
        end

        def image_render_hash?(meta)
          return false unless meta.is_a?(Hash)

          render = meta[:image_render] || meta['image_render']
          render.is_a?(Hash)
        end

        def image_block_metadata(lines)
          meta = first_line_metadata(lines)
          return nil unless image_render_hash?(meta)
          return nil if image_render_line?(meta)

          meta
        end

        def image_render_line?(meta)
          value = meta.key?(:image_render_line) ? meta[:image_render_line] : meta['image_render_line']
          value == true
        rescue StandardError
          false
        end

        def image_line_index(meta)
          value = meta.key?(:image_line_index) ? meta[:image_line_index] : meta['image_line_index']
          value&.to_i
        rescue StandardError
          nil
        end

        def snapped_offset(offset, index)
          snapped = offset.to_i - index.to_i
          snapped.negative? ? 0 : snapped
        rescue StandardError
          offset.to_i
        end
      end
    end
  end
end
