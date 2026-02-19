# frozen_string_literal: true

require_relative '../../application/ports/sidebar_state_reader'
require_relative 'selectors/reader_selectors'

module Shoko
  module Adapters::State
    # Application adapter implementing the SidebarStateReader port.
    # Reads sidebar state from application state using ReaderSelectors.
    class SidebarStateReaderAdapter
      include Application::Ports::SidebarStateReader

      def initialize(state)
        @state = state
      end

      # @return [Boolean] True if sidebar is visible
      def sidebar_visible?
        Selectors::ReaderSelectors.sidebar_visible?(@state)
      end

      # @return [Symbol] Active tab
      def sidebar_active_tab
        Selectors::ReaderSelectors.sidebar_active_tab(@state) || :toc
      end

      # @return [Integer] Selected TOC index
      def sidebar_toc_selected
        Selectors::ReaderSelectors.sidebar_toc_selected(@state) || 0
      end

      # @return [Hash] Hash of collapsed TOC item indices
      def sidebar_toc_collapsed
        Selectors::ReaderSelectors.sidebar_toc_collapsed(@state) || {}
      end

      # @return [Integer] Selected bookmarks index
      def sidebar_bookmarks_selected
        Selectors::ReaderSelectors.sidebar_bookmarks_selected(@state) || 0
      end

      # @return [Integer] Selected annotations index
      def sidebar_annotations_selected
        Selectors::ReaderSelectors.sidebar_annotations_selected(@state) || 0
      end

      # @return [Symbol, nil] Previous view mode
      def sidebar_prev_view_mode
        @state.get(%i[reader sidebar_prev_view_mode])
      end

      # @return [String, nil] TOC filter text
      def sidebar_toc_filter
        Selectors::ReaderSelectors.sidebar_toc_filter(@state)
      end

      # @return [Boolean] True if TOC filter is active
      def sidebar_toc_filter_active?
        Selectors::ReaderSelectors.sidebar_toc_filter_active?(@state)
      end
    end
  end
end
