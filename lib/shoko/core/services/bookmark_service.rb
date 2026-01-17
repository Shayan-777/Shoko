# frozen_string_literal: true

require_relative 'base_service'
require_relative '../events/bookmark_events'

module Shoko
  module Core
    module Services
      # Pure business logic for bookmark management.
      # Replaces the tightly coupled BookmarkService with clean domain logic.
      class BookmarkService < BaseService
        # Add bookmark at current position
        #
        # @param text_snippet [String] Optional text snippet for the bookmark
        # @return [Bookmark] Created bookmark
        def add_bookmark(text_snippet = nil)
          book_path = current_book_path
          return nil unless book_path

          current_state = safe_snapshot
          chapter_index = current_state.dig(:reader, :current_chapter) || 0
          line_offset = get_current_line_offset(current_state)

          bookmark = @bookmark_repository.add_for_book(
            book_path,
            chapter_index: chapter_index,
            line_offset: line_offset,
            text_snippet: text_snippet || generate_text_snippet(current_state)
          )

          refresh_bookmarks(book_path)

          @domain_event_bus.publish(Events::BookmarkAdded.new(
                                      book_path: book_path,
                                      bookmark: bookmark
                                    ))
          @event_bus.emit_event(:bookmark_added, { bookmark: bookmark })
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

          @domain_event_bus.publish(Events::BookmarkRemoved.new(
                                      book_path: book_path,
                                      bookmark: bookmark
                                    ))
          @event_bus.emit_event(:bookmark_removed, { bookmark: bookmark })
        end

        # Get all bookmarks for current book
        #
        # @return [Array<Bookmark>] Array of bookmarks
        def bookmarks
          book_path = current_book_path
          return [] unless book_path

          @bookmark_repository.find_by_book_path(book_path)
        end

        # Navigate to bookmark
        #
        # @param bookmark [Bookmark] Bookmark to navigate to
        def jump_to_bookmark(bookmark)
          snapshot = safe_snapshot
          line_offset = bookmark.line_offset.to_i
          updates = {
            %i[reader current_chapter] => bookmark.chapter_index,
            %i[reader current_page] => line_offset,
          }

          view_mode = snapshot.dig(:config, :view_mode) || :split
          if view_mode == :split
            stride = split_stride_for(snapshot)
            updates[%i[reader left_page]] = line_offset
            updates[%i[reader right_page]] = line_offset + stride
          else
            updates[%i[reader single_page]] = line_offset
          end

          if dynamic_mode?(snapshot)
            page_index = page_index_for(bookmark.chapter_index, line_offset)
            updates[%i[reader current_page_index]] = page_index if page_index
          end

          apply_state_updates(updates)

          # Publish domain event
          @domain_event_bus.publish(Events::BookmarkNavigated.new(
                                      book_path: current_book_path,
                                      bookmark: bookmark
                                    ))

          # Legacy event bus for backward compatibility
          @event_bus.emit_event(:navigated_to_bookmark, { bookmark: bookmark })
        end

        # Check if current position has bookmark
        #
        # @return [Boolean]
        def current_position_bookmarked?
          book_path = current_book_path
          return false unless book_path

          current_state = safe_snapshot
          current_chapter = current_state.dig(:reader, :current_chapter) || 0
          line_offset = get_current_line_offset(current_state)
          @bookmark_repository.exists_at_position?(book_path, current_chapter, line_offset)
        end

        # Get bookmark at current position (if any)
        #
        # @return [Bookmark, nil]
        def bookmark_at_current_position
          book_path = current_book_path
          return nil unless book_path

          current_state = safe_snapshot
          current_chapter = current_state.dig(:reader, :current_chapter) || 0
          line_offset = get_current_line_offset(current_state)
          @bookmark_repository.find_at_position(book_path, current_chapter, line_offset)
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

        protected

        def required_dependencies
          %i[state_store event_bus bookmark_repository domain_event_bus]
        end

        def setup_service_dependencies
          @state_store = resolve(:state_store)
          @event_bus = resolve(:event_bus)
          @bookmark_repository = resolve(:bookmark_repository)
          @domain_event_bus = resolve(:domain_event_bus)
          @page_calculator = resolve(:page_calculator) if registered?(:page_calculator)
          @layout_service = resolve(:layout_service) if registered?(:layout_service)
          @terminal_service = resolve(:terminal_service) if registered?(:terminal_service)
        end

        private

        def get_current_line_offset(state)
          if dynamic_mode?(state)
            offset = line_offset_for_dynamic_state(state)
            return offset if offset
          end

          # Get the current line position depending on view mode
          view_mode = state.dig(:config, :view_mode) || :split
          if view_mode == :split
            state.dig(:reader, :left_page) || 0
          else
            state.dig(:reader, :single_page) || 0
          end
        end

        def dynamic_mode?(state)
          (state.dig(:config, :page_numbering_mode) || :dynamic) == :dynamic
        end

        def page_index_for(chapter_index, line_offset)
          return nil unless @page_calculator

          idx = @page_calculator.find_page_index(chapter_index, line_offset)
          idx && idx >= 0 ? idx : nil
        rescue StandardError
          nil
        end

        def line_offset_for_dynamic_state(state)
          return nil unless @page_calculator

          page_index = state.dig(:reader, :current_page_index) || 0
          page = @page_calculator.get_page(page_index)
          offset = page && (page[:start_line] || page['start_line'])
          offset&.to_i
        rescue StandardError
          nil
        end

        def split_stride_for(state)
          return 1 unless @layout_service

          width = state.dig(:ui, :terminal_width)
          height = state.dig(:ui, :terminal_height)
          height, width = @terminal_service.size if (!width || !height) && @terminal_service
          width = width.to_i
          height = height.to_i
          width = 80 if width <= 0
          height = 24 if height <= 0

          _, content_height = @layout_service.calculate_metrics(width, height, :split)
          spacing = state.dig(:config, :line_spacing) || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
          stride = @layout_service.adjust_for_line_spacing(content_height, spacing)
          stride = 1 if stride.to_i <= 0
          stride
        rescue StandardError
          1
        end

        def generate_text_snippet(state)
          # This would be implemented based on the current document content
          # For now, return a placeholder
          chapter_index = state.dig(:reader, :current_chapter) || 0
          line_offset = get_current_line_offset(state)
          "Chapter #{chapter_index + 1}, Line #{line_offset + 1}"
        end

        def current_book_path
          if @state_store.respond_to?(:get)
            @state_store.get(%i[reader book_path])
          elsif @state_store.respond_to?(:current_state)
            (@state_store.current_state || {}).dig(:reader, :book_path)
          end
        end

        def refresh_bookmarks(book_path = current_book_path)
          return unless book_path

          bookmarks = @bookmark_repository.find_by_book_path(book_path)
          apply_state_updates({ %i[reader bookmarks] => bookmarks })
        end

        def apply_state_updates(updates)
          return if updates.nil? || updates.empty?

          if @state_store.respond_to?(:update)
            @state_store.update(updates)
          elsif @state_store.respond_to?(:set)
            updates.each { |path, value| @state_store.set(path, value) }
          end
        end

        def safe_snapshot
          return {} unless @state_store.respond_to?(:current_state)

          @state_store.current_state || {}
        rescue StandardError
          {}
        end
      end
    end
  end
end
