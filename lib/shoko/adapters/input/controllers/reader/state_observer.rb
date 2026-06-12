# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Applies UI/render reactions to observed reader/config state changes.
          class StateObserver
            def initialize(controller:, progress_autosave: nil)
              @controller = controller
              @progress_autosave = progress_autosave
            end

            def handle(path, new_value)
              return handle_reader_change(path, new_value) if path.first == :reader

              handle_config_change(path)
            end

            private

            def handle_reader_change(path, new_value)
              case path
              when %i[reader mode] then handle_mode_change(new_value)
              when %i[reader dictionary_visible] then @controller.rebuild_root_layout
              when %i[reader current_chapter] then @progress_autosave&.note_chapter_change
              when %i[reader single_page], %i[reader left_page], %i[reader current_page_index]
                @progress_autosave&.note_position_change
              end
            end

            def handle_config_change(path)
              case path
              when %i[config theme] then handle_theme_change
              when %i[config
                      view_mode], %i[config line_spacing], %i[config page_numbering_mode], %i[config kitty_images]
                handle_layout_change
              end
            end

            def handle_mode_change(new_value)
              @controller.activate_input_for_mode(new_value)
            end

            def handle_theme_change
              theme_context = @controller.apply_theme_palette
              @controller.ui_controller&.refresh_theme(theme_context: theme_context)
              @controller.request_render
            end

            def handle_layout_change
              @controller.pagination_coordinator&.rebuild_after_config_change
              @controller.request_render
            end
          end
        end
      end
    end
  end
end
