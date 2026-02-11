# frozen_string_literal: true

require_relative 'pagination_state_writer'
require_relative 'reader_state_writer'

module Shoko
  module Core
    module Ports
      # Deprecated compatibility port. Prefer PaginationStateWriter and
      # ReaderStateWriter in new code.
      # Port interface for writing state changes.
      # Adapters implementing this interface handle state updates without
      # coupling core services to specific state management implementations.
      #
      # This allows core domain services to signal state changes without
      # knowing about Redux-style actions or any specific state management pattern.
      #
      # @example Implementing this port
      #   class StateWriterAdapter
      #     include Shoko::Core::Ports::StateWriter
      #
      #     def initialize(state)
      #       @state = state
      #     end
      #
      #     def update_pagination_state(attrs)
      #       @state.dispatch(UpdatePaginationStateAction.new(attrs))
      #     end
      #   end
      module StateWriter
        include PaginationStateWriter
        include ReaderStateWriter

        # Update pagination-related state
        #
        # @param attrs [Hash] Pagination attributes to update
        #   - :total_pages [Integer] Total number of pages
        #   - :current_chapter_index [Integer] Current chapter index
        #   - :total_chapters [Integer] Total number of chapters
        #   - :chapter_page_count [Integer] Pages in current chapter
        #   - :chapter_start_page [Integer] Starting page of current chapter
        # @return [void]
        def update_pagination_state(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_pagination_state"
        end

        # Update current page position
        #
        # @param attrs [Hash] Page attributes to update
        #   - :current_page_index [Integer] Current page index
        # @return [void]
        def update_page(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_page"
        end

        # Update selection-related state
        #
        # @param attrs [Hash] Selection attributes to update
        #   - :pending_progress [Hash, nil] Pending progress state
        # @return [void]
        def update_selections(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_selections"
        end

        # Update UI loading state
        #
        # @param attrs [Hash] Loading attributes to update
        #   - :loading [Boolean] Whether loading is in progress
        #   - :loading_message [String, nil] Loading message to display
        #   - :loading_progress [Float, nil] Progress percentage (0.0-1.0)
        # @return [void]
        def update_ui_loading(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_ui_loading"
        end

        # Update UI dimensions state
        #
        # @param attrs [Hash] Dimension attributes to update
        #   - :terminal_width [Integer] Terminal width in columns
        #   - :terminal_height [Integer] Terminal height in rows
        # @return [void]
        def update_ui_dimensions(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_ui_dimensions"
        end

        # Update reader-related state
        #
        # @param attrs [Hash] Reader attributes to update
        #   - :annotations [Array] List of annotations
        # @return [void]
        def update_reader(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_reader"
        end

        # Update navigation-related state
        #
        # @param attrs [Hash] Navigation attributes to update
        #   - :current_chapter [Integer] Current chapter index
        #   - :current_page_index [Integer] Current page index (dynamic mode)
        #   - :current_page [Integer] Current page offset (absolute mode)
        #   - :left_page [Integer] Left page offset (split view)
        #   - :right_page [Integer] Right page offset (split view)
        #   - :single_page [Integer] Single page offset (single view)
        # @return [void]
        def update_navigation(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_navigation"
        end

        # Update bookmarks in state
        #
        # @param bookmarks [Array] Array of bookmarks
        # @return [void]
        def update_bookmarks(bookmarks)
          raise NotImplementedError, "#{self.class} must implement #update_bookmarks"
        end

        # Update configuration state
        #
        # @param attrs [Hash] Config attributes to update
        #   - :view_mode [Symbol] View mode (:single or :split)
        #   - :line_spacing [Integer] Line spacing value
        #   - :page_numbering_mode [Symbol] Page numbering mode (:dynamic or :absolute)
        #   - :show_page_numbers [Boolean] Whether to show page numbers
        #   - :theme [Symbol] Theme identifier
        # @return [void]
        def update_config(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_config"
        end

        # Update sidebar state
        #
        # @param attrs [Hash] Sidebar attributes to update
        #   - :sidebar_visible [Boolean] Whether sidebar is visible
        #   - :sidebar_active_tab [Symbol] Active tab (:toc, :bookmarks, :annotations)
        #   - :sidebar_toc_selected [Integer] Selected TOC index
        #   - :sidebar_bookmarks_selected [Integer] Selected bookmarks index
        #   - :sidebar_annotations_selected [Integer] Selected annotations index
        # @return [void]
        def update_sidebar(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_sidebar"
        end

        # Update annotations in state
        #
        # @param annotations [Array] Array of annotations
        # @return [void]
        def update_annotations(annotations)
          raise NotImplementedError, "#{self.class} must implement #update_annotations"
        end

        # Clear selection state
        #
        # @return [void]
        def clear_selection
          raise NotImplementedError, "#{self.class} must implement #clear_selection"
        end

        # Signal quit-to-menu (sets running = false)
        #
        # @return [void]
        def quit_to_menu
          raise NotImplementedError, "#{self.class} must implement #quit_to_menu"
        end

        # Toggle view mode between :single and :split
        #
        # @return [void]
        def toggle_view_mode
          raise NotImplementedError, "#{self.class} must implement #toggle_view_mode"
        end

        # Update reader meta fields (book_path, running)
        #
        # @param attrs [Hash] Meta attributes to update
        # @return [void]
        def update_reader_meta(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_reader_meta"
        end
      end
    end
  end
end
