# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Applies UI/render reactions to observed reader/config state changes.
          class StateObserver
            def initialize(controller:)
              @controller = controller
            end

            def handle(path, new_value)
              case path
              when %i[reader sidebar_visible] then handle_sidebar_visibility(new_value)
              when %i[reader dictionary_visible] then @controller.rebuild_root_layout
              when %i[config theme] then handle_theme_change
              when %i[config
                      view_mode], %i[config line_spacing], %i[config page_numbering_mode], %i[config kitty_images]
                handle_layout_change
              end
            end

            private

            def handle_sidebar_visibility(new_value)
              @controller.pagination_coordinator&.sync_sidebar_layout(sidebar_visible: new_value == true)
              @controller.rebuild_root_layout
              @controller.force_redraw
            end

            def handle_theme_change
              theme_context = @controller.apply_theme_palette
              @controller.ui_controller&.refresh_theme(theme_context: theme_context)
              @controller.force_redraw
            end

            def handle_layout_change
              @controller.pagination_coordinator&.rebuild_after_config_change
              @controller.force_redraw
            end
          end
        end
      end
    end
  end
end
