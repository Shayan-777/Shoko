# frozen_string_literal: true

require_relative 'base_action'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        module Actions
          # Action for updating sidebar state
          class UpdateSidebarAction < BaseAction
            SIDEBAR_UPDATE_PATHS = {
              visible: %i[reader sidebar_visible],
              active_tab: %i[reader sidebar_active_tab],
              toc_selected: %i[reader sidebar_toc_selected],
              toc_collapsed: %i[reader sidebar_toc_collapsed],
              annotations_selected: %i[reader sidebar_annotations_selected],
              bookmarks_selected: %i[reader sidebar_bookmarks_selected],
            }.freeze

            def initialize(**updates)
              super(updates)
            end

            def apply(state)
              # Build update hash for atomic state update
              state.update(sidebar_updates)
            end

            def sidebar_updates
              payload.each_with_object({}) do |(field, value), updates|
                path = SIDEBAR_UPDATE_PATHS[field]
                updates[path] = value if path
              end
            end
          end
        end
      end
    end
  end
end
