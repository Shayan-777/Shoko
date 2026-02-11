# frozen_string_literal: true

require_relative 'reader_navigation_reader'
require_relative 'reader_overlay_reader'

module Shoko
  module Core
    module Ports
      # Deprecated compatibility port. Prefer ReaderNavigationReader and
      # ReaderOverlayReader in new code.
      # Port interface for reading reader/navigation state.
      # Adapters implementing this interface provide access to reader state
      # without coupling core services to application state schema.
      #
      # @example Implementing this port
      #   class ReaderStateReaderAdapter
      #     include Shoko::Core::Ports::ReaderStateReader
      #
      #     def initialize(state)
      #       @state = state
      #     end
      #
      #     def current_chapter
      #       @state.get([:reader, :current_chapter])
      #     end
      #   end
      module ReaderStateReader
        include ReaderNavigationReader
        include ReaderOverlayReader

        # Get the current chapter index (0-based)
        #
        # @return [Integer] Current chapter index
        def current_chapter
          raise NotImplementedError, "#{self.class} must implement #current_chapter"
        end

        # Get the total number of chapters
        #
        # @return [Integer] Total chapter count
        def total_chapters
          raise NotImplementedError, "#{self.class} must implement #total_chapters"
        end

        # Get the current page index (dynamic mode)
        #
        # @return [Integer] Current page index
        def current_page_index
          raise NotImplementedError, "#{self.class} must implement #current_page_index"
        end

        # Get the left page offset (split view, absolute mode)
        #
        # @return [Integer] Left page line offset
        def left_page
          raise NotImplementedError, "#{self.class} must implement #left_page"
        end

        # Get the right page offset (split view, absolute mode)
        #
        # @return [Integer] Right page line offset
        def right_page
          raise NotImplementedError, "#{self.class} must implement #right_page"
        end

        # Get the single page offset (single view, absolute mode)
        #
        # @return [Integer] Single page line offset
        def single_page
          raise NotImplementedError, "#{self.class} must implement #single_page"
        end

        # Get the current page offset (absolute mode)
        #
        # @return [Integer] Current page line offset
        def current_page
          raise NotImplementedError, "#{self.class} must implement #current_page"
        end

        # Get the page map for absolute pagination
        #
        # @return [Array] Page map array
        def page_map
          raise NotImplementedError, "#{self.class} must implement #page_map"
        end

        # Get the current book file path
        #
        # @return [String, nil] Book file path
        def book_path
          raise NotImplementedError, "#{self.class} must implement #book_path"
        end

        # Get the bookmarks for the current book
        #
        # @return [Array] Array of bookmarks
        def bookmarks
          raise NotImplementedError, "#{self.class} must implement #bookmarks"
        end

        # Get the total number of pages (dynamic mode)
        #
        # @return [Integer] Total page count
        def total_pages
          raise NotImplementedError, "#{self.class} must implement #total_pages"
        end

        # Get the pending progress data for restoration
        #
        # @return [Hash, nil] Pending progress hash
        def pending_progress
          raise NotImplementedError, "#{self.class} must implement #pending_progress"
        end

        # Get the annotations for the current book
        #
        # @return [Array] Array of annotations
        def annotations
          raise NotImplementedError, "#{self.class} must implement #annotations"
        end

        # Get the current reader mode
        #
        # @return [Symbol] Current mode (:normal, :selection, :dictionary, etc.)
        def mode
          raise NotImplementedError, "#{self.class} must implement #mode"
        end

        # Get the current selection
        #
        # @return [Hash, nil] Selection data
        def selection
          raise NotImplementedError, "#{self.class} must implement #selection"
        end

        # Get the popup menu state
        #
        # @return [Hash, nil] Popup menu data
        def popup_menu
          raise NotImplementedError, "#{self.class} must implement #popup_menu"
        end

        # Get the in-book search popup state
        #
        # @return [Hash, nil] In-book search popup data
        def in_book_search_popup
          raise NotImplementedError, "#{self.class} must implement #in_book_search_popup"
        end

        # Get the annotations overlay state
        #
        # @return [Hash, nil] Annotations overlay data
        def annotations_overlay
          raise NotImplementedError, "#{self.class} must implement #annotations_overlay"
        end

        # Get the annotation editor overlay state
        #
        # @return [Hash, nil] Annotation editor overlay data
        def annotation_editor_overlay
          raise NotImplementedError, "#{self.class} must implement #annotation_editor_overlay"
        end

        # Get the dictionary popup state
        #
        # @return [Hash, nil] Dictionary popup data
        def dictionary_popup
          raise NotImplementedError, "#{self.class} must implement #dictionary_popup"
        end

        # Get the dictionary panel state
        #
        # @return [Hash, nil] Dictionary panel data
        def dictionary_panel
          raise NotImplementedError, "#{self.class} must implement #dictionary_panel"
        end

        # Get the current message
        #
        # @return [String, nil] Status message
        def message
          raise NotImplementedError, "#{self.class} must implement #message"
        end

        # Check if reader is running
        #
        # @return [Boolean] True if reader is active
        def running?
          raise NotImplementedError, "#{self.class} must implement #running?"
        end

        # Get sidebar annotations selected index
        #
        # @return [Integer, nil] Selected annotation index in sidebar
        def sidebar_annotations_selected
          raise NotImplementedError, "#{self.class} must implement #sidebar_annotations_selected"
        end

        # Get the active sidebar tab
        #
        # @return [Symbol, nil] Active tab (:toc, :annotations, :bookmarks)
        def sidebar_active_tab
          raise NotImplementedError, "#{self.class} must implement #sidebar_active_tab"
        end

        # Check if sidebar is visible
        #
        # @return [Boolean] True if sidebar is visible
        def sidebar_visible?
          raise NotImplementedError, "#{self.class} must implement #sidebar_visible?"
        end

        # Get the pending jump payload
        #
        # @return [Hash, nil] Pending jump data
        def pending_jump
          raise NotImplementedError, "#{self.class} must implement #pending_jump"
        end

        # Get the last terminal width
        #
        # @return [Integer, nil] Last terminal width
        def last_width
          raise NotImplementedError, "#{self.class} must implement #last_width"
        end
      end
    end
  end
end
