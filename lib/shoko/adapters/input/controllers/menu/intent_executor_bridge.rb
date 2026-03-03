# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/menu_intent_executor'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Adapter-owned execution bridge for menu intent dispatch.
          class IntentExecutorBridge
            include Shoko::Core::Ports::Outbound::MenuIntentExecutor

            def initialize(menu_controller:)
              @menu_controller = menu_controller
            end

            def execute(intent_symbol:, payload: nil)
              key = payload&.key

              case intent_symbol.to_sym
              when :annotation_editor_backspace then @menu_controller.annotation_editor_backspace(key)
              when :annotation_editor_cancel then @menu_controller.annotation_editor_cancel(key)
              when :annotation_editor_enter then @menu_controller.annotation_editor_enter(key)
              when :annotation_editor_insert_char then @menu_controller.annotation_editor_insert_char(key)
              when :annotation_editor_move_down then @menu_controller.annotation_editor_move_down(key)
              when :annotation_editor_move_left then @menu_controller.annotation_editor_move_left(key)
              when :annotation_editor_move_right then @menu_controller.annotation_editor_move_right(key)
              when :annotation_editor_move_up then @menu_controller.annotation_editor_move_up(key)
              when :annotation_editor_save then @menu_controller.annotation_editor_save(key)
              when :annotations_down then @menu_controller.annotations_down(key)
              when :annotations_select then @menu_controller.annotations_select(key)
              when :annotations_up then @menu_controller.annotations_up(key)
              when :browse_down then @menu_controller.browse_down(key)
              when :browse_up then @menu_controller.browse_up(key)
              when :delete_selected_annotation then @menu_controller.delete_selected_annotation(key)
              when :dictionary_back then @menu_controller.dictionary_back(key)
              when :dictionary_down then @menu_controller.dictionary_down(key)
              when :dictionary_exit_search then @menu_controller.dictionary_exit_search(key)
              when :dictionary_refresh then @menu_controller.dictionary_refresh(key)
              when :dictionary_search_backspace then @menu_controller.dictionary_search_backspace(key)
              when :dictionary_search_delete then @menu_controller.dictionary_search_delete(key)
              when :dictionary_search_insert_char then @menu_controller.dictionary_search_insert_char(key)
              when :dictionary_select then @menu_controller.dictionary_select(key)
              when :dictionary_start_search then @menu_controller.dictionary_start_search(key)
              when :dictionary_submit_search then @menu_controller.dictionary_submit_search(key)
              when :dictionary_up then @menu_controller.dictionary_up(key)
              when :download_confirm then @menu_controller.download_confirm(key)
              when :download_down then @menu_controller.download_down(key)
              when :download_exit_search then @menu_controller.download_exit_search(key)
              when :download_next_page then @menu_controller.download_next_page(key)
              when :download_prev_page then @menu_controller.download_prev_page(key)
              when :download_refresh then @menu_controller.download_refresh(key)
              when :download_search_backspace then @menu_controller.download_search_backspace(key)
              when :download_search_delete then @menu_controller.download_search_delete(key)
              when :download_search_insert_char then @menu_controller.download_search_insert_char(key)
              when :download_start_search then @menu_controller.download_start_search(key)
              when :download_submit_search then @menu_controller.download_submit_search(key)
              when :download_up then @menu_controller.download_up(key)
              when :library_down then @menu_controller.library_down(key)
              when :library_select then @menu_controller.library_select(key)
              when :library_toggle_details then @menu_controller.library_toggle_details(key)
              when :library_up then @menu_controller.library_up(key)
              when :menu_back_to_root then @menu_controller.menu_back_to_root(key)
              when :menu_nav_down then @menu_controller.menu_nav_down(key)
              when :menu_nav_up then @menu_controller.menu_nav_up(key)
              when :menu_quit then @menu_controller.menu_quit(key)
              when :menu_select then @menu_controller.menu_select(key)
              when :open_selected_annotation then @menu_controller.open_selected_annotation(key)
              when :open_selected_annotation_for_edit then @menu_controller.open_selected_annotation_for_edit(key)
              when :open_selected_book then @menu_controller.open_selected_book(key)
              when :search_backspace then @menu_controller.search_backspace(key)
              when :search_delete then @menu_controller.search_delete(key)
              when :search_insert_char then @menu_controller.search_insert_char(key)
              when :settings_down then @menu_controller.settings_down(key)
              when :settings_select then @menu_controller.settings_select(key)
              when :settings_up then @menu_controller.settings_up(key)
              when :switch_to_annotations_mode then @menu_controller.switch_to_annotations_mode(key)
              when :switch_to_browse then @menu_controller.switch_to_browse(key)
              when :switch_to_search then @menu_controller.switch_to_search(key)
              else
                raise ArgumentError, "Unsupported menu intent: #{intent_symbol}"
              end
            end
          end
        end
      end
    end
  end
end
