# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/menu_intent_executor'
require_relative '../../../../core/ports/inbound/menu_intent_handler'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Adapter-owned execution bridge for menu intent dispatch.
          class IntentExecutorBridge
            include Shoko::Core::Ports::Outbound::MenuIntentExecutor

            INTENT_DISPATCH = {
              annotation_editor_backspace: :annotation_editor_backspace,
              annotation_editor_cancel: :annotation_editor_cancel,
              annotation_editor_enter: :annotation_editor_enter,
              annotation_editor_insert_char: :annotation_editor_insert_char,
              annotation_editor_move_down: :annotation_editor_move_down,
              annotation_editor_move_left: :annotation_editor_move_left,
              annotation_editor_move_right: :annotation_editor_move_right,
              annotation_editor_move_up: :annotation_editor_move_up,
              annotation_editor_save: :annotation_editor_save,
              annotations_down: :annotations_down,
              annotations_select: :annotations_select,
              annotations_up: :annotations_up,
              browse_down: :browse_down,
              browse_up: :browse_up,
              delete_selected_annotation: :delete_selected_annotation,
              dictionary_back: :dictionary_back,
              dictionary_down: :dictionary_down,
              dictionary_exit_search: :dictionary_exit_search,
              dictionary_refresh: :dictionary_refresh,
              dictionary_search_backspace: :dictionary_search_backspace,
              dictionary_search_delete: :dictionary_search_delete,
              dictionary_search_insert_char: :dictionary_search_insert_char,
              dictionary_select: :dictionary_select,
              dictionary_start_search: :dictionary_start_search,
              dictionary_submit_search: :dictionary_submit_search,
              dictionary_up: :dictionary_up,
              download_confirm: :download_confirm,
              download_down: :download_down,
              download_exit_search: :download_exit_search,
              download_next_page: :download_next_page,
              download_prev_page: :download_prev_page,
              download_refresh: :download_refresh,
              download_search_backspace: :download_search_backspace,
              download_search_delete: :download_search_delete,
              download_search_insert_char: :download_search_insert_char,
              download_start_search: :download_start_search,
              download_submit_search: :download_submit_search,
              download_up: :download_up,
              library_down: :library_down,
              library_select: :library_select,
              library_toggle_details: :library_toggle_details,
              library_up: :library_up,
              menu_back_to_root: :menu_back_to_root,
              menu_nav_down: :menu_nav_down,
              menu_nav_up: :menu_nav_up,
              menu_quit: :menu_quit,
              menu_select: :menu_select,
              open_selected_annotation: :open_selected_annotation,
              open_selected_annotation_for_edit: :open_selected_annotation_for_edit,
              open_selected_book: :open_selected_book,
              search_backspace: :search_backspace,
              search_delete: :search_delete,
              search_insert_char: :search_insert_char,
              settings_down: :settings_down,
              settings_select: :settings_select,
              settings_up: :settings_up,
              switch_to_annotations_mode: :switch_to_annotations_mode,
              switch_to_browse: :switch_to_browse,
              switch_to_search: :switch_to_search
            }.freeze

            def initialize(menu_controller:)
              @menu_controller = menu_controller
              validate_dispatch_contract!
              validate_controller_methods!
            end

            def execute(intent_symbol:, payload: nil)
              key = payload&.key
              intent = intent_symbol.to_sym
              method_name = INTENT_DISPATCH[intent]
              raise ArgumentError, "Unsupported menu intent: #{intent_symbol}" unless method_name

              @menu_controller.public_send(method_name, key)
            end

            private

            def validate_dispatch_contract!
              expected = Shoko::Core::Ports::Inbound::MenuIntentHandler::INTENT_SYMBOLS.sort
              actual = INTENT_DISPATCH.keys.sort
              return if expected == actual

              missing = expected - actual
              extra = actual - expected
              raise ArgumentError, "Menu intent dispatch mismatch missing=#{missing.inspect} extra=#{extra.inspect}"
            end

            def validate_controller_methods!
              missing = INTENT_DISPATCH.values.uniq.reject { |method_name| @menu_controller.respond_to?(method_name, true) }
              return if missing.empty?

              raise ArgumentError, "Menu controller missing dispatch methods: #{missing.join(', ')}"
            end
          end
        end
      end
    end
  end
end
