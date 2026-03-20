# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Reader
        # Navigation and page-resolution helpers for bookmark operations.
        module BookmarkServiceNavigationSupport
          def jump_to_bookmark(bookmark)
            update_navigation(navigation_attributes_for(bookmark))
            publish_bookmark_event(
              Shoko::Core::Events::BookmarkNavigated,
              book_path: current_book_path,
              bookmark: bookmark
            )
          end

          def current_position_bookmarked?
            book_path = current_book_path
            return false unless book_path

            @bookmark_repository.exists_at_position?(book_path, current_chapter, current_line_offset)
          end

          def bookmark_at_current_position
            book_path = current_book_path
            return nil unless book_path

            @bookmark_repository.find_at_position(book_path, current_chapter, current_line_offset)
          end

          private

          def navigation_attributes_for(bookmark)
            line_offset = bookmark.line_offset.to_i
            attrs = { current_chapter: bookmark.chapter_index, current_page: line_offset }
            merge_view_mode_navigation!(attrs, line_offset)
            merge_dynamic_navigation!(attrs, bookmark.chapter_index, line_offset)
            attrs
          end

          def merge_view_mode_navigation!(attrs, line_offset)
            if current_view_mode == :split
              stride = split_stride
              attrs[:left_page] = line_offset
              attrs[:right_page] = line_offset + stride
            else
              attrs[:single_page] = line_offset
            end
          end

          def merge_dynamic_navigation!(attrs, chapter_index, line_offset)
            return unless dynamic_mode?

            page_index = page_index_for(chapter_index, line_offset)
            attrs[:current_page_index] = page_index if page_index
          end

          def current_line_offset
            return resolved_dynamic_line_offset if dynamic_mode?

            current_view_mode == :split ? left_page : single_page
          end

          def resolved_dynamic_line_offset
            offset = line_offset_for_dynamic_state
            return offset if offset

            current_view_mode == :split ? left_page : single_page
          end

          def dynamic_mode?
            page_numbering_mode == :dynamic
          end

          def page_index_for(chapter_index, line_offset)
            return nil unless @page_calculator

            idx = @page_calculator.find_page_index(chapter_index, line_offset)
            idx && idx >= 0 ? idx : nil
          rescue Shoko::Error => e
            logger.debug('bookmark.page_index_for failed', error: e.message)
            nil
          end

          def line_offset_for_dynamic_state
            return nil unless @page_calculator

            page = @page_calculator.get_page(
              current_page_index,
              width: terminal_width,
              height: terminal_height,
              sidebar_visible: @reader_state_reader.sidebar_visible?
            )
            offset = page_start_line(page)
            offset&.to_i
          rescue Shoko::Error => e
            logger.debug('bookmark.line_offset_for_dynamic_state failed', error: e.message)
            nil
          end

          def page_start_line(page)
            return nil unless page.is_a?(Hash)
            return page[:start_line] if page.key?(:start_line)
            raise ArgumentError, 'page payload must use symbol keys' if page.key?('start_line')

            nil
          end

          def split_stride
            return 1 unless @layout_service

            width = [terminal_width.to_i, 80].max
            height = [terminal_height.to_i, 24].max
            _, content_height = @layout_service.calculate_metrics(width, height, :split)
            stride = @layout_service.adjust_for_line_spacing(content_height, line_spacing)
            stride.to_i <= 0 ? 1 : stride
          rescue Shoko::Error => e
            logger.debug('bookmark.split_stride failed', error: e.message)
            1
          end
        end
      end
    end
  end
end
