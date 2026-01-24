# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for reading sidebar state.
      # Adapters implementing this interface provide access to sidebar state
      # without coupling core services to application state schema.
      #
      # @example Implementing this port
      #   class SidebarStateReaderAdapter
      #     include Shoko::Core::Ports::SidebarStateReader
      #
      #     def initialize(state)
      #       @state = state
      #     end
      #
      #     def sidebar_visible?
      #       @state.get([:reader, :sidebar_visible])
      #     end
      #   end
      module SidebarStateReader
        # Check if the sidebar is currently visible
        #
        # @return [Boolean] True if sidebar is visible
        def sidebar_visible?
          raise NotImplementedError, "#{self.class} must implement #sidebar_visible?"
        end

        # Get the currently active sidebar tab
        #
        # @return [Symbol] Active tab (:toc, :bookmarks, :annotations)
        def sidebar_active_tab
          raise NotImplementedError, "#{self.class} must implement #sidebar_active_tab"
        end

        # Get the selected index in the TOC tab
        #
        # @return [Integer] Selected TOC index
        def sidebar_toc_selected
          raise NotImplementedError, "#{self.class} must implement #sidebar_toc_selected"
        end

        # Get the collapsed state of TOC items
        #
        # @return [Hash] Hash of collapsed TOC item indices
        def sidebar_toc_collapsed
          raise NotImplementedError, "#{self.class} must implement #sidebar_toc_collapsed"
        end

        # Get the selected index in the bookmarks tab
        #
        # @return [Integer] Selected bookmarks index
        def sidebar_bookmarks_selected
          raise NotImplementedError, "#{self.class} must implement #sidebar_bookmarks_selected"
        end

        # Get the selected index in the annotations tab
        #
        # @return [Integer] Selected annotations index
        def sidebar_annotations_selected
          raise NotImplementedError, "#{self.class} must implement #sidebar_annotations_selected"
        end

        # Get the previous view mode before sidebar was opened
        #
        # @return [Symbol, nil] Previous view mode (:single or :split)
        def sidebar_prev_view_mode
          raise NotImplementedError, "#{self.class} must implement #sidebar_prev_view_mode"
        end

        # Get the TOC filter text
        #
        # @return [String, nil] TOC filter text
        def sidebar_toc_filter
          raise NotImplementedError, "#{self.class} must implement #sidebar_toc_filter"
        end

        # Check if TOC filter is active
        #
        # @return [Boolean] True if TOC filter is active
        def sidebar_toc_filter_active?
          raise NotImplementedError, "#{self.class} must implement #sidebar_toc_filter_active?"
        end
      end
    end
  end
end
