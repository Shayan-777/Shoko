# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          module Actions
            module Navigation
              def handle_menu_selection
                case @menu_state_reader.selected
                when 0 then switch_to_browse
                when 1 then switch_to_mode(:library)
                when 2 then switch_to_mode(:annotations)
                when 3 then open_download_screen
                when 4 then switch_to_mode(:settings)
                when 5 then cleanup_and_exit(0, '')
                end
              end

              def handle_navigation(direction)
                current = @menu_state_reader.selected
                max_val = 5

                new_selected = case direction
                               when :up then [current - 1, 0].max
                               when :down then [current + 1, max_val].min
                               else current
                               end
                @menu_state_writer.update_menu(selected: new_selected)
              end

              def switch_to_browse
                @menu_state_writer.update_menu(mode: :browse, search_active: false)
                input_controller.activate(@menu_state_reader.mode)
              end

              def switch_to_search
                @menu_state_writer.update_menu(mode: :search, search_active: true)
                input_controller.activate(@menu_state_reader.mode)
              end

              def switch_to_mode(mode)
                payload = { mode: mode, browse_selected: 0 }
                payload[:settings_selected] = 1 if mode == :settings
                @menu_state_writer.update_menu(payload)
                preload_annotations if mode == :annotations
                input_controller.activate(@menu_state_reader.mode)
              end

              def refresh_scan(force: true)
                state_controller.refresh_scan(force: force)
              end

              def library_up
                current = @menu_state_reader.browse_selected || 0
                @menu_state_writer.update_menu(browse_selected: (current - 1).clamp(0, current))
              end

              def library_down
                items = if main_menu_component&.current_screen.respond_to?(:items)
                          main_menu_component.current_screen.items
                        else
                          []
                        end
                max_index = [items.length - 1, 0].max
                current = @menu_state_reader.browse_selected || 0
                @menu_state_writer.update_menu(browse_selected: (current + 1).clamp(0, max_index))
              end

              def library_select
                item = selected_library_item
                return unless item

                target_path = resolve_library_path(item)
                return state_controller.file_not_found unless target_path

                state_controller.run_reader(target_path)
              end

              def open_selected_book
                state_controller.open_selected_book
              end

              # Annotation helpers (public so dispatcher can invoke explicitly)
              def open_selected_annotation
                state_controller.open_selected_annotation
              end

              def open_selected_annotation_for_edit
                state_controller.open_selected_annotation_for_edit
              end

              def annotations_up
                @main_menu_component&.annotations_screen&.navigate(:up)
              end

              def annotations_down
                @main_menu_component&.annotations_screen&.navigate(:down)
              end

              def annotations_select
                context = selected_annotation_context
                annotation = context[:annotation]
                book_path = context[:book_path]
                return unless annotation && book_path

                @menu_state_writer.update_menu(selected_annotation: annotation, selected_annotation_book: book_path)
                switch_to_mode(:annotation_detail)
              end

              def delete_selected_annotation
                state_controller.delete_selected_annotation
              end

              def browse_items_count
                if @main_menu_component&.browse_screen
                  @main_menu_component.browse_screen.filtered_count
                else
                  Array(@filtered_epubs).length
                end
              rescue StandardError
                Array(@filtered_epubs).length
              end

              def save_current_annotation_edit
                state_controller.save_current_annotation_edit
              end

              # Current editor component exposed for annotation editor command routing.
              def current_editor_component
                return nil unless @menu_state_reader.mode == :annotation_editor

                @main_menu_component&.annotation_edit_screen
              end
            end
          end
        end
      end
    end
  end
end
