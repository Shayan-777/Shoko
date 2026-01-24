# frozen_string_literal: true

module Shoko
  module Core
    module Ports
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
      end
    end
  end
end
