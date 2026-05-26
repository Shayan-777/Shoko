# frozen_string_literal: true

require_relative '../../../core/services/base_service'
require_relative '../../../core/events/bookmark_events'
require_relative '../../../core/models/reader_settings'
require_relative '../../../application/ports/outbound/app_config_store'
require_relative '../../../application/ports/outbound/reader_session_store'
require_relative '../../../application/ports/outbound/reader_runtime_context'
require_relative 'bookmark_service/navigation_support'

module Shoko
  module Application
    module Services
      module Reader
        # Pure business logic for bookmark management.
        # Uses session stores/runtime context instead of state-slice ports.
        class BookmarkService < Shoko::Core::Services::BaseService
          include BookmarkServiceNavigationSupport

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
        end
      end
    end
  end
end
