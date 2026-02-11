# frozen_string_literal: true

require_relative '../../core/ports/pagination_state_writer'
require_relative '../../core/ports/reader_state_writer'
require_relative 'actions/update_pagination_state_action'
require_relative 'actions/update_ui_loading_action'
require_relative 'actions/update_state_action'
require_relative 'actions/update_config_action'
require_relative 'actions/update_sidebar_action'
require_relative 'actions/quit_to_menu_action'
require_relative 'actions/toggle_view_mode_action'
require_relative 'actions/update_reader_meta_action'

module Shoko
  module Adapters::State
    # Application adapter implementing the StateWriter port.
    # Dispatches appropriate actions to update application state.
    class StateWriterAdapter
      include Core::Ports::PaginationStateWriter
      include Core::Ports::ReaderStateWriter

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
        @state.dispatch(Actions::UpdateReaderAction.new(**attrs))
      end

      # Update selection-related state
      # @param attrs [Hash] Selection attributes (e.g., pending_progress)
      def update_selections(attrs)
        @state.dispatch(Actions::UpdateReaderAction.new(**attrs))
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
        @state.dispatch(Actions::UpdateReaderAction.new(selection: nil))
      end

      # Signal quit-to-menu
      def quit_to_menu
        @state.dispatch(Actions::QuitToMenuAction.new)
      end

      # Toggle view mode between :single and :split
      def toggle_view_mode
        @state.dispatch(Actions::ToggleViewModeAction.new)
      end

      # Update reader meta fields (book_path, running)
      # @param attrs [Hash] Meta attributes
      def update_reader_meta(attrs)
        @state.dispatch(Actions::UpdateReaderMetaAction.new(**attrs))
      end
    end
  end
end
