# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module StateControllerBookmarkActions
          def load_bookmarks
            canonical = canonical_path_for_doc
            bookmarks = @bookmark_repository.find_by_book_path(canonical)
            @state_writer.update_reader(bookmarks: bookmarks)
          end

          def add_bookmark
            if @bookmark_service
              @bookmark_service.add_bookmark
            else
              position = current_bookmark_position
              canonical = canonical_path_for_doc
              begin
                @bookmark_repository.add_for_book(canonical,
                                                  chapter_index: position[:chapter],
                                                  line_offset: position[:line_offset],
                                                  text_snippet: '')
                bookmarks = @bookmark_repository.find_by_book_path(canonical)
              rescue StandardError
                bookmarks = @reader_state.bookmarks || []
              end
              @state_writer.update_reader(bookmarks: bookmarks)
            end

            curr_ch = @reader_state.current_chapter || 0
            curr_page = current_page_label
            set_message("Bookmark added at Chapter #{curr_ch + 1}, Page #{curr_page}")
          end

          def jump_to_bookmark
            bookmarks = bookmarks_list
            selected_idx = @sidebar_state.sidebar_bookmarks_selected || 0
            bookmark = bookmarks[selected_idx]
            return unless bookmark

            chapter_index = bookmark.chapter_index
            if @navigation_service
              @navigation_service.jump_to_chapter(chapter_index)
            else
              @state_writer.update_reader(current_chapter: chapter_index)
            end

            offset = bookmark.line_offset.to_i
            stride = split_stride_for_state
            payload = {
              single_page: offset,
              left_page: offset,
              right_page: offset + stride,
              current_page: offset,
            }

            if @config_reader.page_numbering_mode == :dynamic && @page_calculator
              page_index = @page_calculator.find_page_index(chapter_index, offset)
              payload[:current_page_index] = page_index if page_index
            end

            @state_writer.update_page(**payload)
            save_progress
            @state_writer.update_reader(mode: :read)
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
            @state_writer.update_sidebar(bookmarks_selected: max_selected)
            set_message('Bookmark deleted!')
          end

          private

          def split_stride_for_state
            return 1 unless @layout_service

            width = @ui_state.terminal_width
            height = @ui_state.terminal_height
            height, width = @terminal_service.size if (!width || !height) && @terminal_service
            width = width.to_i
            height = height.to_i
            width = 80 if width <= 0
            height = 24 if height <= 0

            _, content_height = @layout_service.calculate_metrics(width, height, :split)
            spacing = @config_reader.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
            stride = @layout_service.adjust_for_line_spacing(content_height, spacing)
            stride = 1 if stride.to_i <= 0
            stride
          rescue StandardError
            1
          end

          def current_bookmark_position
            chapter = @reader_state.current_chapter || 0
            if dynamic_page_numbering? && @page_calculator
              page_index = @reader_state.current_page_index || 0
              width = @ui_state.terminal_width
              height = @ui_state.terminal_height
              height, width = @terminal_service.size if (!width || !height) && @terminal_service
              page = @page_calculator.get_page(
                page_index,
                width: width,
                height: height,
                sidebar_visible: @reader_state.sidebar_visible? == true
              )
              if page
                chapter = page[:chapter_index] || chapter
                line = page[:start_line] || page['start_line']
                return { chapter: chapter, line_offset: line.to_i }
              end
            end

            view_mode = @config_reader.view_mode
            line_offset = view_mode == :split ? @reader_state.left_page : @reader_state.single_page
            { chapter: chapter, line_offset: line_offset || 0 }
          rescue StandardError
            { chapter: chapter, line_offset: 0 }
          end

          def current_page_label
            if dynamic_page_numbering?
              ((@reader_state.current_page_index || 0).to_i + 1)
            else
              @reader_state.current_page || 0
            end
          rescue StandardError
            0
          end

          def dynamic_page_numbering?
            @config_reader.page_numbering_mode == :dynamic
          rescue StandardError
            false
          end

          def bookmarks_list
            @reader_state.bookmarks
          end
        end
      end
    end
  end
end
