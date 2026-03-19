# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          class IntentRuntimeBridge
            # Maps reader intents onto sidebar visibility, tab, and selection commands.
            module SidebarActions
              def show_toc_sidebar
                controller.open_toc
              end

              def show_bookmarks_sidebar
                controller.open_bookmarks
              end

              def show_annotations_sidebar
                controller.open_annotations_tab
              end

              def toggle_sidebar_visibility
                controller.sidebar_toggle_toc
              end

              def move_sidebar_selection(delta:)
                delta.negative? ? controller.sidebar_up : controller.sidebar_down
              end

              def activate_sidebar_selection
                controller.sidebar_select
              end
            end
          end
        end
      end
    end
  end
end
