# frozen_string_literal: true

require_relative '../../core/ports/reader_state_reader'
require_relative '../selectors/reader_selectors'

module Shoko
  module Application
    module Adapters
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
          @state.get([:reader, :total_chapters]) || 0
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
          @state.get([:reader, :current_page]) || 0
        end

        # @return [Array] Page map array
        def page_map
          Selectors::ReaderSelectors.page_map(@state)
        end

        # @return [String, nil] Book file path
        def book_path
          @state.get([:reader, :book_path])
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
          @state.get([:reader, :pending_progress])
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
      end
    end
  end
end
