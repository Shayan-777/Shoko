# frozen_string_literal: true

require_relative '../../../../core/models/reader_settings'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Reader-state actions for bookmark CRUD and bookmark navigation.
        module StateControllerBookmarkActions
          def load_bookmarks
            canonical = canonical_path_for_doc
            bookmarks = @bookmark_repository.find_by_book_path(canonical)
            @reader_session_mutator.update_reader(bookmarks: bookmarks)
          end

          def add_bookmark
            persist_bookmark
            set_message("Bookmark added at Chapter #{current_chapter_label}, Page #{current_page_label}")
          end

          def jump_to_bookmark
            bookmark = selected_bookmark
            return unless bookmark

            chapter_index = bookmark.chapter_index
            jump_to_bookmark_chapter(chapter_index)
            apply_bookmark_position(chapter_index, bookmark.line_offset.to_i)
          end

          def delete_selected_bookmark
            bookmarks = bookmarks_list
            selected_idx = @sidebar_state.sidebar_bookmarks_selected || 0
            bookmark = bookmarks[selected_idx]
            return unless bookmark

            canonical = canonical_path_for_doc
            @bookmark_repository.delete_for_book(canonical, bookmark)
            load_bookmarks
            current_bookmarks = bookmarks_list
            max_selected = if current_bookmarks.any?
                             [selected_idx, current_bookmarks.length - 1].min
                           else
                             0
                           end
            @reader_session_mutator.update_sidebar(bookmarks_selected: max_selected)
            set_message('Bookmark deleted!')
          end

          private

          def persist_bookmark
            return @bookmark_service.add_bookmark if @bookmark_service

            sync_bookmarks_from_repository
          end

          def sync_bookmarks_from_repository
            position = current_bookmark_position
            canonical = canonical_path_for_doc
            bookmarks = fetch_bookmarks_after_add(canonical, position)
            @reader_session_mutator.update_reader(bookmarks: bookmarks)
          end

          def fetch_bookmarks_after_add(canonical, position)
            @bookmark_repository.add_for_book(
              canonical,
              chapter_index: position[:chapter],
              line_offset: position[:line_offset],
              text_snippet: ''
            )
            @bookmark_repository.find_by_book_path(canonical)
          rescue Shoko::Error
            @reader_state.bookmarks || []
          end

          def selected_bookmark
            bookmarks = bookmarks_list
            selected_idx = @sidebar_state.sidebar_bookmarks_selected || 0
            bookmarks[selected_idx]
          end

          def jump_to_bookmark_chapter(chapter_index)
            if @navigation_service
              @navigation_service.jump_to_chapter(chapter_index)
            else
              @reader_session_mutator.update_reader(current_chapter: chapter_index)
            end
          end

          def apply_bookmark_position(chapter_index, offset)
            payload = bookmark_position_payload(offset)
            page_index = bookmark_page_index(chapter_index, offset)
            payload[:current_page_index] = page_index if page_index
            @reader_session_mutator.update_reader(**payload)
            save_progress
            @reader_session_mutator.update_reader(mode: :read)
          end

          def bookmark_position_payload(offset)
            stride = split_stride_for_state
            { single_page: offset, left_page: offset, right_page: offset + stride, current_page: offset }
          end

          def bookmark_page_index(chapter_index, offset)
            return nil unless dynamic_page_numbering? && @page_calculator

            @page_calculator.find_page_index(chapter_index, offset)
          end

          def split_stride_for_state
            return 1 unless @layout_service

            width, height = layout_dimensions
            _, content_height = @layout_service.calculate_metrics(width, height, :split)
            spacing = current_line_spacing
            stride = @layout_service.adjust_for_line_spacing(content_height, spacing)
            normalized_stride(stride)
          end

          def current_bookmark_position
            chapter = @reader_state.current_chapter || 0
            dynamic_bookmark_position(chapter) || absolute_bookmark_position(chapter)
          rescue Shoko::Error
            { chapter: chapter, line_offset: 0 }
          end

          def dynamic_bookmark_position(chapter)
            return nil unless dynamic_page_numbering? && @page_calculator

            width, height = layout_dimensions
            page = @page_calculator.get_page(
              @reader_state.current_page_index || 0,
              width: width,
              height: height,
              sidebar_visible: @reader_state.sidebar_visible? == true
            )
            return nil unless page

            {
              chapter: page[:chapter_index] || chapter,
              line_offset: page[:start_line].to_i,
            }
          end

          def absolute_bookmark_position(chapter)
            view_mode = @config_reader.view_mode
            line_offset = view_mode == :split ? @reader_state.left_page : @reader_state.single_page
            { chapter: chapter, line_offset: line_offset || 0 }
          end

          def layout_dimensions
            width = @ui_state.terminal_width
            height = @ui_state.terminal_height
            return normalized_dimensions(width, height) unless (!width || !height) && @terminal_service

            term_height, term_width = @terminal_service.size
            normalized_dimensions(term_width, term_height)
          end

          def normalized_dimensions(width, height)
            width_value = width.to_i
            height_value = height.to_i
            width_value = 80 if width_value <= 0
            height_value = 24 if height_value <= 0
            [width_value, height_value]
          end

          def current_line_spacing
            @config_reader.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
          end

          def normalized_stride(stride)
            stride_value = stride.to_i
            stride_value.positive? ? stride_value : 1
          end

          def current_chapter_label
            (@reader_state.current_chapter || 0) + 1
          end

          def current_page_label
            if dynamic_page_numbering?
              ((@reader_state.current_page_index || 0).to_i + 1)
            else
              @reader_state.current_page || 0
            end
          end

          def dynamic_page_numbering?
            @config_reader.page_numbering_mode == :dynamic
          end

          def bookmarks_list
            @reader_state.bookmarks
          end
        end
      end
    end
  end
end
