# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          class IntentRuntimeBridge
            module SidebarActions
              def sidebar_visible?
                controller.sidebar_visible?
              end

              def sidebar_toc_tab?
                controller.reader_state_reader.sidebar_active_tab == :toc
              end

              def open_toc_sidebar
                controller.open_toc
              end

              def open_bookmarks_sidebar
                controller.open_bookmarks
              end

              def open_annotations_sidebar
                controller.open_annotations_tab
              end

              def toggle_sidebar
                controller.sidebar_toggle_toc
              end

              def sidebar_move(delta)
                delta.negative? ? controller.sidebar_up : controller.sidebar_down
              end

              def sidebar_activate
                controller.sidebar_select
              end
            end
          end
        end
      end
    end
  end
end
