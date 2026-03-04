# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/reader_intent_executor'
require_relative '../../../../core/ports/inbound/reader_intent_handler'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Adapter-owned execution bridge for reader intent dispatch.
          class IntentExecutorBridge
            include Shoko::Core::Ports::Outbound::ReaderIntentExecutor

            INTENT_DISPATCH = {
              annotation_editor_backspace: [:annotation_editor_backspace, false],
              annotation_editor_cancel: [:annotation_editor_cancel, false],
              annotation_editor_enter: [:annotation_editor_enter, false],
              annotation_editor_insert_char_if_printable: [:annotation_editor_insert_char_if_printable, true],
              annotation_editor_move_down: [:annotation_editor_move_down, false],
              annotation_editor_move_left: [:annotation_editor_move_left, false],
              annotation_editor_move_right: [:annotation_editor_move_right, false],
              annotation_editor_move_up: [:annotation_editor_move_up, false],
              annotation_editor_save: [:annotation_editor_save, false],
              decrease_line_spacing: [:decrease_line_spacing, false],
              dictionary_backspace: [:dictionary_backspace, false],
              dictionary_cancel: [:dictionary_cancel, false],
              dictionary_confirm: [:dictionary_confirm, false],
              dictionary_cycle_pair: [:dictionary_cycle_pair, false],
              dictionary_cycle_result: [:dictionary_cycle_result, false],
              dictionary_insert_char_if_printable: [:dictionary_insert_char_if_printable, true],
              dictionary_scroll_down: [:dictionary_scroll_down, false],
              dictionary_scroll_up: [:dictionary_scroll_up, false],
              dictionary_swap_languages: [:dictionary_swap_languages, false],
              dictionary_toggle_fuzzy: [:dictionary_toggle_fuzzy, false],
              handle_popup_action_key: [:handle_popup_action_key, true],
              handle_popup_cancel: [:handle_popup_cancel, true],
              handle_popup_navigation: [:handle_popup_navigation, true],
              help_exit_to_read: [:help_exit_to_read, false],
              in_book_search_backspace: [:in_book_search_backspace, false],
              in_book_search_cancel: [:in_book_search_cancel, false],
              in_book_search_confirm: [:in_book_search_confirm, false],
              in_book_search_down: [:in_book_search_down, false],
              in_book_search_insert_char_if_printable: [:in_book_search_insert_char_if_printable, true],
              in_book_search_up: [:in_book_search_up, false],
              increase_line_spacing: [:increase_line_spacing, false],
              invalidate_pagination_cache: [:invalidate_pagination_cache, false],
              open_annotations: [:open_annotations, false],
              open_annotations_tab: [:open_annotations_tab, false],
              open_bookmarks: [:open_bookmarks, false],
              open_in_book_search: [:open_in_book_search, false],
              open_toc: [:open_toc, false],
              quit_application: [:quit_application, false],
              quit_to_menu: [:quit_to_menu, false],
              read_confirm_or_sidebar: [:read_confirm_or_sidebar, false],
              read_scroll_down_or_sidebar: [:read_scroll_down_or_sidebar, false],
              read_scroll_up_or_sidebar: [:read_scroll_up_or_sidebar, false],
              read_space_or_sidebar_toggle: [:read_space_or_sidebar_toggle, false],
              rebuild_pagination: [:rebuild_pagination, false],
              show_help: [:show_help, false],
              toggle_page_numbering_mode: [:toggle_page_numbering_mode, false],
              toggle_view_mode: [:toggle_view_mode, false]
            }.freeze

            def initialize(reader_controller:)
              @reader_controller = reader_controller
              validate_dispatch_contract!
              validate_controller_methods!
            end

            def execute(intent_symbol:, payload: nil)
              key = payload&.key
              intent = intent_symbol.to_sym
              entry = INTENT_DISPATCH[intent]
              raise ArgumentError, "Unsupported reader intent: #{intent_symbol}" unless entry

              method_name, pass_key = entry
              args = pass_key ? [key] : []
              @reader_controller.public_send(method_name, *args)
            end

            private

            def validate_dispatch_contract!
              expected = Shoko::Core::Ports::Inbound::ReaderIntentHandler::INTENT_SYMBOLS.sort
              actual = INTENT_DISPATCH.keys.sort
              return if expected == actual

              missing = expected - actual
              extra = actual - expected
              raise ArgumentError, "Reader intent dispatch mismatch missing=#{missing.inspect} extra=#{extra.inspect}"
            end

            def validate_controller_methods!
              missing = INTENT_DISPATCH.values.map(&:first).uniq.reject do |method_name|
                @reader_controller.respond_to?(method_name, true)
              end
              return if missing.empty?

              raise ArgumentError, "Reader controller missing dispatch methods: #{missing.join(', ')}"
            end
          end
        end
      end
    end
  end
end
