# frozen_string_literal: true

require_relative '../../core/ports/reader_state_reader'
require_relative 'selectors/reader_selectors'

module Shoko
  module Adapters::State
    # Application adapter implementing the ReaderStateReader port.
    # Reads reader/navigation state using ReaderSelectors.
    class ReaderStateReaderAdapter
      include Core::Ports::ReaderStateReader

      def initialize(state)
        @state = state
      end

      # @return [Integer] Current chapter index (0-based)
      def current_chapter
        Selectors::ReaderSelectors.current_chapter(@state) || 0
      end

      # @return [Integer] Total chapter count
      def total_chapters
        @state.get(%i[reader total_chapters]) || 0
      end

      # @return [Integer] Current page index (dynamic mode)
      def current_page_index
        Selectors::ReaderSelectors.current_page_index(@state) || 0
      end

      # @return [Integer] Left page line offset
      def left_page
        Selectors::ReaderSelectors.left_page(@state) || 0
      end

      # @return [Integer] Right page line offset
      def right_page
        Selectors::ReaderSelectors.right_page(@state) || 0
      end

      # @return [Integer] Single page line offset
      def single_page
        Selectors::ReaderSelectors.single_page(@state) || 0
      end

      # @return [Integer] Current page line offset
      def current_page
        @state.get(%i[reader current_page]) || 0
      end

      # @return [Array] Page map array
      def page_map
        Selectors::ReaderSelectors.page_map(@state)
      end

      # @return [String, nil] Book file path
      def book_path
        @state.get(%i[reader book_path])
      end

      # @return [Array] Array of bookmarks
      def bookmarks
        Selectors::ReaderSelectors.bookmarks(@state)
      end

      # @return [Integer] Total page count
      def total_pages
        Selectors::ReaderSelectors.total_pages(@state) || 0
      end

      # @return [Hash, nil] Pending progress hash
      def pending_progress
        @state.get(%i[reader pending_progress])
      end

      # @return [Array] Array of annotations
      def annotations
        Selectors::ReaderSelectors.annotations(@state)
      end

      # @return [Symbol] Current mode
      def mode
        Selectors::ReaderSelectors.mode(@state) || :normal
      end

      # @return [Hash, nil] Selection data
      def selection
        Selectors::ReaderSelectors.selection(@state)
      end

      # @return [Hash, nil] Popup menu data
      def popup_menu
        Selectors::ReaderSelectors.popup_menu(@state)
      end

      # @return [Hash, nil] In-book search popup data
      def in_book_search_popup
        Selectors::ReaderSelectors.in_book_search_popup(@state)
      end

      # @return [Hash, nil] Annotations overlay data
      def annotations_overlay
        Selectors::ReaderSelectors.annotations_overlay(@state)
      end

      # @return [Hash, nil] Annotation editor overlay data
      def annotation_editor_overlay
        Selectors::ReaderSelectors.annotation_editor_overlay(@state)
      end

      # @return [Hash, nil] Dictionary popup data
      def dictionary_popup
        Selectors::ReaderSelectors.dictionary_popup(@state)
      end

      # @return [Hash, nil] Dictionary panel data
      def dictionary_panel
        @state.get(%i[reader dictionary_panel])
      end

      # @return [String, nil] Status message
      def message
        Selectors::ReaderSelectors.message(@state)
      end

      # @return [Boolean] True if reader is active
      def running?
        Selectors::ReaderSelectors.running?(@state)
      end

      # @return [Integer, nil] Selected annotation index in sidebar
      def sidebar_annotations_selected
        Selectors::ReaderSelectors.sidebar_annotations_selected(@state)
      end

      # @return [Symbol, nil] Active sidebar tab
      def sidebar_active_tab
        Selectors::ReaderSelectors.sidebar_active_tab(@state)
      end

      # @return [Boolean] True if sidebar is visible
      def sidebar_visible?
        @state.get(%i[reader sidebar_visible]) == true
      end

      # @return [Hash, nil] Pending jump data
      def pending_jump
        @state.get(%i[reader pending_jump])
      end

      # @return [Integer, nil] Last terminal width
      def last_width
        @state.get(%i[reader last_width])
      end
    end
  end
end
