# frozen_string_literal: true

require_relative '../../core/ports/state_writer'
require_relative '../state/actions/update_pagination_state_action'
require_relative '../state/actions/update_page_action'
require_relative '../state/actions/update_selections_action'
require_relative '../state/actions/update_ui_loading_action'
require_relative '../state/actions/update_state_action'
require_relative '../state/actions/update_config_action'
require_relative '../state/actions/update_sidebar_action'
require_relative '../state/actions/update_selection_action'

module Shoko
  module Application
    module Adapters
      # Application adapter implementing the StateWriter port.
      # Dispatches appropriate actions to update application state.
      class StateWriterAdapter
        include Core::Ports::StateWriter

        def initialize(state)
          @state = state
        end

        # Update pagination-related state
        # @param attrs [Hash] Pagination attributes
        def update_pagination_state(attrs)
          @state.dispatch(Actions::UpdatePaginationStateAction.new(**attrs))
        end

        # Update current page position
        # @param attrs [Hash] Page attributes (e.g., current_page_index)
        def update_page(attrs)
          @state.dispatch(Actions::UpdatePageAction.new(**attrs))
        end

        # Update selection-related state
        # @param attrs [Hash] Selection attributes (e.g., pending_progress)
        def update_selections(attrs)
          @state.dispatch(Actions::UpdateSelectionsAction.new(**attrs))
        end

        # Update UI loading state
        # @param attrs [Hash] Loading attributes (e.g., loading_active, loading_message)
        def update_ui_loading(attrs)
          @state.dispatch(Actions::UpdateUILoadingAction.new(**attrs))
        end

        # Update UI dimensions state
        # @param attrs [Hash] Dimension attributes (e.g., terminal_width, terminal_height)
        def update_ui_dimensions(attrs)
          @state.dispatch(Actions::UpdateUIAction.new(**attrs))
        end

        # Update reader-related state
        # @param attrs [Hash] Reader attributes (e.g., annotations)
        def update_reader(attrs)
          @state.dispatch(Actions::UpdateReaderAction.new(**attrs))
        end

        # Update navigation-related state
        # @param attrs [Hash] Navigation attributes (e.g., current_chapter, left_page)
        def update_navigation(attrs)
          @state.dispatch(Actions::UpdateReaderAction.new(**attrs))
        end

        # Update bookmarks in state
        # @param bookmarks [Array] Array of bookmarks
        def update_bookmarks(bookmarks)
          @state.dispatch(Actions::UpdateReaderAction.new(bookmarks: bookmarks))
        end

        # Update configuration state
        # @param attrs [Hash] Config attributes
        def update_config(attrs)
          @state.dispatch(Actions::UpdateConfigAction.new(**attrs))
        end

        # Update sidebar state
        # @param attrs [Hash] Sidebar attributes
        def update_sidebar(attrs)
          @state.dispatch(Actions::UpdateSidebarAction.new(**attrs))
        end

        # Update annotations in state
        # @param annotations [Array] Array of annotations
        def update_annotations(annotations)
          @state.dispatch(Actions::UpdateReaderAction.new(annotations: annotations))
        end

        # Clear selection state
        def clear_selection
          @state.dispatch(Actions::ClearSelectionAction.new)
        end
      end
    end
  end
end
