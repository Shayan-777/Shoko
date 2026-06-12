# frozen_string_literal: true

require_relative '../../../../application/ports/outbound/application_exit_control'
require_relative '../../../../application/ports/outbound/menu_annotation_control'
require_relative '../../../../application/ports/outbound/menu_browse_inspection'
require_relative '../../../../application/ports/outbound/menu_download_selection'
require_relative '../../../../application/ports/outbound/menu_translator_control'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Aggregates the menu action ports implemented against the menu controller.
          class IntentRuntimeBridge
            include Shoko::Application::Ports::Outbound::ApplicationExitControl
            include Shoko::Application::Ports::Outbound::MenuAnnotationControl
            include Shoko::Application::Ports::Outbound::MenuBrowseInspection
            include Shoko::Application::Ports::Outbound::MenuDownloadSelection
            include Shoko::Application::Ports::Outbound::MenuTranslatorControl

            def initialize(menu_state_reader:, browse_screen:, library_screen:, annotations_screen:,
                           annotation_edit_screen:, translator_screen:, cache_path_validator:, exit_handler:)
              @menu_state_reader = menu_state_reader
              @browse_screen = browse_screen
              @library_screen = library_screen
              @annotations_screen = annotations_screen
              @annotation_edit_screen = annotation_edit_screen
              @translator_screen = translator_screen
              @cache_path_validator = cache_path_validator
              @exit_handler = exit_handler
            end

            def browse_item_count
              @browse_screen.filtered_count
            end

            def library_item_count
              Array(@library_screen.items).length
            end

            def selected_library_path
              item = selected_library_item
              return nil unless item

              path = item.open_path
              return path if @cache_path_validator.valid_cache_path?(path)

              nil
            end

            # The selected book's source path — the key the pre-pagination batch
            # tracks status by, so the open-gate can tell whether it is ready.
            def selected_library_source_path
              selected_library_item&.epub_path
            end

            def selected_download_result
              results = Array(@menu_state_reader.download_results)
              index = (@menu_state_reader.download_selected || 0).to_i
              results[index]
            end

            def move_annotation_selection(delta:)
              direction = delta.negative? ? :up : :down
              @annotations_screen.navigate(direction)
            end

            def selected_annotation_context
              {
                annotation: @annotations_screen.current_annotation,
                book_path: @annotations_screen.current_book_path,
              }
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

            def move_translator_cursor(direction:)
              editor = translator_editor
              return :pass unless editor

              case direction
              when :left then editor.handle_move_left
              when :right then editor.handle_move_right
              when :up then editor.handle_move_up
              when :down then editor.handle_move_down
              end
            end

            def quit_application(code:, message:)
              @exit_handler.call(code, message)
            end

            private

            def selected_library_item
              items = @library_screen.items
              index = (@menu_state_reader.browse_selected || 0).to_i
              items[index]
            end

            def annotation_editor
              return nil unless @menu_state_reader.mode == :annotation_editor

              @annotation_edit_screen
            end

            def translator_editor
              return nil unless @menu_state_reader.mode == :translator
              return nil unless (@menu_state_reader.translator_focus || :input).to_sym == :input

              @translator_screen
            end
          end
        end
      end
    end
  end
end
