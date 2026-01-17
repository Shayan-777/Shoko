# frozen_string_literal: true

module Shoko
  module Core
    module Ports
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

        # Update reader-related state
        #
        # @param attrs [Hash] Reader attributes to update
        #   - :annotations [Array] List of annotations
        # @return [void]
        def update_reader(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_reader"
        end
      end
    end
  end
end
