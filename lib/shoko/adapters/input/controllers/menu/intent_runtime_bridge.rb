# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/application_exit_control'
require_relative '../../../../core/ports/outbound/menu_annotation_control'
require_relative '../../../../core/ports/outbound/menu_browse_inspection'
require_relative '../../../../core/ports/outbound/menu_download_selection'
require_relative '../../../../core/ports/outbound/menu_mode_control'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Aggregates the menu action ports implemented against the menu controller.
          class IntentRuntimeBridge
            include Shoko::Core::Ports::Outbound::ApplicationExitControl
            include Shoko::Core::Ports::Outbound::MenuAnnotationControl
            include Shoko::Core::Ports::Outbound::MenuBrowseInspection
            include Shoko::Core::Ports::Outbound::MenuDownloadSelection
            include Shoko::Core::Ports::Outbound::MenuModeControl

            def initialize(menu:)
              @menu = menu
            end

            def activate_menu_mode(mode)
              @menu.input_controller.activate(mode)
            end

            def browse_item_count
              @menu.main_menu_component.browse_screen.filtered_count
            end

            def library_item_count
              Array(@menu.main_menu_component.library_screen.items).length
            end

            def selected_library_path
              item = selected_library_item
              return nil unless item

              path = item.open_path
              return path if @menu.state_controller.valid_cache_path?(path)

              nil
            end

            def selected_download_result
              results = Array(@menu.menu_state_reader.download_results)
              index = (@menu.menu_state_reader.download_selected || 0).to_i
              results[index]
            end

            def move_annotation_selection(delta:)
              direction = delta.negative? ? :up : :down
              @menu.main_menu_component.annotations_screen.navigate(direction)
            end

            def selected_annotation_context
              @menu.selected_annotation_for_workflow
            end

            def append_annotation_text(text)
              editor = annotation_editor
              return :pass unless editor

              editor.handle_character(text.to_s)
            end

            def delete_annotation_character
              editor = annotation_editor
              return :pass unless editor

              editor.handle_backspace
            end

            def insert_annotation_newline
              editor = annotation_editor
              return :pass unless editor

              editor.handle_enter
            end

            def move_annotation_cursor(direction:)
              editor = annotation_editor
              return :pass unless editor

              case direction
              when :left then editor.handle_move_left
              when :right then editor.handle_move_right
              when :up then editor.handle_move_up
              when :down then editor.handle_move_down
              end
            end

            def save_annotation
              editor = annotation_editor
              return :pass unless editor

              editor.save_annotation
            end

            def cancel_annotation
              editor = annotation_editor
              return :pass unless editor

              editor.cancel_annotation
            end

            def quit_application(code:, message:)
              @menu.cleanup_and_exit(code, message)
            end

            private

            def selected_library_item
              items = @menu.main_menu_component.library_screen.items
              index = (@menu.menu_state_reader.browse_selected || 0).to_i
              items[index]
            end

            def annotation_editor
              return nil unless @menu.menu_state_reader.mode == :annotation_editor

              @menu.main_menu_component.annotation_edit_screen
            end
          end
        end
      end
    end
  end
end
