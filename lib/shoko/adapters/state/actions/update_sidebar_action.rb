# frozen_string_literal: true

require_relative 'base_action'

module Shoko
  module Adapters::State::Actions
    # Action for updating sidebar state
    class UpdateSidebarAction < BaseAction
      def initialize(**updates)
        super(updates)
      end

      def apply(state)
        # Build update hash for atomic state update
        updates = {}
        payload.each do |field, value|
          case field
          when :visible
            updates[%i[reader sidebar_visible]] = value
          when :active_tab
            updates[%i[reader sidebar_active_tab]] = value
          when :toc_selected
            updates[%i[reader sidebar_toc_selected]] = value
          when :toc_collapsed
            updates[%i[reader sidebar_toc_collapsed]] = value
          when :annotations_selected
            updates[%i[reader sidebar_annotations_selected]] = value
          when :bookmarks_selected
            updates[%i[reader sidebar_bookmarks_selected]] = value
          end
        end
        state.update(updates)
      end
    end
  end
end
