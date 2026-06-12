# frozen_string_literal: true

require 'shoko/core/services/base_service'
require 'shoko/core/events/bookmark_events'
require 'shoko/core/models/reader_settings'
require 'shoko/application/ports/outbound/app_config_store'
require 'shoko/application/ports/outbound/reader_session_store'
require 'shoko/application/ports/outbound/reader_runtime_context'

module Shoko
  module Application
    module Services
      module Reader
        # Pure business logic for bookmark management.
        # Uses session stores/runtime context instead of state-slice ports.
        class BookmarkService < Shoko::Core::Services::BaseService
          def initialize(bookmark_repository:, domain_event_bus:,
                         domain_event_factory:,
                         app_config_store:, reader_session_store:, reader_runtime_context:,
                         reader_state_reader: nil,
                         page_calculator: nil, layout_service: nil,
                         logger: nil)
            super(logger: logger)
            @bookmark_repository = bookmark_repository
            @domain_event_bus = domain_event_bus
            @domain_event_factory = domain_event_factory
            @app_config_store = app_config_store
            @reader_session_store = reader_session_store
            @reader_state_reader = reader_state_reader || reader_session_store
            @reader_runtime_context = reader_runtime_context
            @page_calculator = page_calculator
            @layout_service = layout_service
          end

          # Add bookmark at current position
          #
          # @param text_snippet [String] Optional text snippet for the bookmark
          # @return [Bookmark] Created bookmark
          def add_bookmark(text_snippet = nil)
            book_path = current_book_path
            return nil unless book_path

            bookmark = create_bookmark(book_path, text_snippet)
            refresh_bookmarks(book_path)
            publish_bookmark_event(Shoko::Core::Events::BookmarkAdded, book_path: book_path, bookmark: bookmark)
            bookmark
          end

          # Remove bookmark
          #
          # @param bookmark [Bookmark] Bookmark to remove
          def remove_bookmark(bookmark)
            book_path = current_book_path
            return unless book_path

            @bookmark_repository.delete_for_book(book_path, bookmark)
            refresh_bookmarks(book_path)
            publish_bookmark_event(Shoko::Core::Events::BookmarkRemoved, book_path: book_path, bookmark: bookmark)
          end

          # Get all bookmarks for current book
          #
          # @return [Array<Bookmark>] Array of bookmarks
          def bookmarks
            book_path = current_book_path
            return [] unless book_path

            @bookmark_repository.find_by_book_path(book_path)
          end

          # Toggle bookmark at current position
          #
          # @param text_snippet [String] Text snippet if adding
          # @return [Symbol] :added or :removed
          def toggle_bookmark(text_snippet = nil)
            existing_bookmark = bookmark_at_current_position

            if existing_bookmark
              remove_bookmark(existing_bookmark)
              :removed
            else
              add_bookmark(text_snippet)
              :added
            end
          end

          # Jump to bookmark — updates navigation state and emits event.
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

          def current_chapter
            current_reader.current_chapter || 0
          end

          def current_view_mode
            current_config.view_mode || :single
          end

          def page_numbering_mode
            current_config.page_numbering_mode || :dynamic
          end

          def line_spacing
            current_config.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
          end

          def terminal_width
            current_terminal_size.width || 80
          end

          def terminal_height
            current_terminal_size.height || 24
          end

          def left_page
            current_reader.left_page || 0
          end

          def single_page
            current_reader.single_page || 0
          end

          def current_page_index
            current_reader.current_page_index || 0
          end

          def current_book_path
            current_reader.book_path
          end

          def update_navigation(attrs)
            @reader_session_store.save(current_reader.with(**attrs))
          end

          def update_bookmarks(bookmarks_list)
            @reader_session_store.save(current_reader.with(bookmarks: bookmarks_list))
          end

          def create_bookmark(book_path, text_snippet)
            @bookmark_repository.add_for_book(
              book_path,
              chapter_index: current_chapter,
              line_offset: current_line_offset,
              text_snippet: text_snippet || generate_text_snippet
            )
          end

          def publish_bookmark_event(event_class, book_path:, bookmark:)
            @domain_event_bus.publish(
              @domain_event_factory.build(event_class, book_path: book_path, bookmark: bookmark)
            )
          end

          def generate_text_snippet
            chapter_idx = current_chapter
            offset = current_line_offset
            "Chapter #{chapter_idx + 1}, Line #{offset + 1}"
          end

          def refresh_bookmarks(book_path = current_book_path)
            return unless book_path

            bookmarks_list = @bookmark_repository.find_by_book_path(book_path)
            update_bookmarks(bookmarks_list)
          end

          def current_config
            @app_config_store.load
          end

          def current_reader
            @reader_session_store.load
          end

          def current_terminal_size
            @reader_runtime_context.terminal_size
          end

          # ─── Navigation/page-resolution helpers (folded in from
          # `bookmark_service/navigation_support.rb`) ───

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
              height: terminal_height
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
