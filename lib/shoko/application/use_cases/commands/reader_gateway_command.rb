# frozen_string_literal: true

require_relative '../../../core/ports/inbound/reader_command_gateway'
require_relative 'input_command_payload'

module Shoko
  module Application
    module UseCases
      module Commands
        # Explicit gateway command dispatch for reader-bound input symbols.
        class ReaderGatewayCommand
          class InvalidPayloadError < StandardError; end
          class ContractMismatchError < StandardError; end

          def initialize(command_symbol)
            @command_symbol = command_symbol.to_sym
          end

          def execute(context, payload = nil)
            validate_context!(context)
            normalized_payload = normalize_payload(payload)
            result = dispatch(context, normalized_payload.key)
            result.nil? ? :handled : result
          end

          private

          def validate_context!(context)
            return if context.is_a?(Shoko::Core::Ports::Inbound::ReaderCommandGateway)

            raise ContractMismatchError,
                  "Context must implement #{Shoko::Core::Ports::Inbound::ReaderCommandGateway}"
          end

          def normalize_payload(payload)
            InputCommandPayload.from(payload)
          rescue ArgumentError => e
            raise InvalidPayloadError, e.message
          end

          def dispatch(context, key)
            case @command_symbol
            when :annotation_editor_backspace then invoke_with_optional_key(context, :annotation_editor_backspace, key)
            when :annotation_editor_cancel then invoke_with_optional_key(context, :annotation_editor_cancel, key)
            when :annotation_editor_enter then invoke_with_optional_key(context, :annotation_editor_enter, key)
            when :annotation_editor_insert_char_if_printable then invoke_with_optional_key(context, :annotation_editor_insert_char_if_printable, key)
            when :annotation_editor_move_down then invoke_with_optional_key(context, :annotation_editor_move_down, key)
            when :annotation_editor_move_left then invoke_with_optional_key(context, :annotation_editor_move_left, key)
            when :annotation_editor_move_right then invoke_with_optional_key(context, :annotation_editor_move_right, key)
            when :annotation_editor_move_up then invoke_with_optional_key(context, :annotation_editor_move_up, key)
            when :annotation_editor_save then invoke_with_optional_key(context, :annotation_editor_save, key)
            when :decrease_line_spacing then invoke_with_optional_key(context, :decrease_line_spacing, key)
            when :dictionary_backspace then invoke_with_optional_key(context, :dictionary_backspace, key)
            when :dictionary_cancel then invoke_with_optional_key(context, :dictionary_cancel, key)
            when :dictionary_confirm then invoke_with_optional_key(context, :dictionary_confirm, key)
            when :dictionary_cycle_pair then invoke_with_optional_key(context, :dictionary_cycle_pair, key)
            when :dictionary_cycle_result then invoke_with_optional_key(context, :dictionary_cycle_result, key)
            when :dictionary_insert_char_if_printable then invoke_with_optional_key(context, :dictionary_insert_char_if_printable, key)
            when :dictionary_scroll_down then invoke_with_optional_key(context, :dictionary_scroll_down, key)
            when :dictionary_scroll_up then invoke_with_optional_key(context, :dictionary_scroll_up, key)
            when :dictionary_swap_languages then invoke_with_optional_key(context, :dictionary_swap_languages, key)
            when :dictionary_toggle_fuzzy then invoke_with_optional_key(context, :dictionary_toggle_fuzzy, key)
            when :handle_popup_action_key then invoke_with_optional_key(context, :handle_popup_action_key, key)
            when :handle_popup_cancel then invoke_with_optional_key(context, :handle_popup_cancel, key)
            when :handle_popup_navigation then invoke_with_optional_key(context, :handle_popup_navigation, key)
            when :help_exit_to_read then invoke_with_optional_key(context, :help_exit_to_read, key)
            when :in_book_search_backspace then invoke_with_optional_key(context, :in_book_search_backspace, key)
            when :in_book_search_cancel then invoke_with_optional_key(context, :in_book_search_cancel, key)
            when :in_book_search_confirm then invoke_with_optional_key(context, :in_book_search_confirm, key)
            when :in_book_search_down then invoke_with_optional_key(context, :in_book_search_down, key)
            when :in_book_search_insert_char_if_printable then invoke_with_optional_key(context, :in_book_search_insert_char_if_printable, key)
            when :in_book_search_up then invoke_with_optional_key(context, :in_book_search_up, key)
            when :increase_line_spacing then invoke_with_optional_key(context, :increase_line_spacing, key)
            when :invalidate_pagination_cache then invoke_with_optional_key(context, :invalidate_pagination_cache, key)
            when :open_annotations then invoke_with_optional_key(context, :open_annotations, key)
            when :open_annotations_tab then invoke_with_optional_key(context, :open_annotations_tab, key)
            when :open_bookmarks then invoke_with_optional_key(context, :open_bookmarks, key)
            when :open_in_book_search then invoke_with_optional_key(context, :open_in_book_search, key)
            when :open_toc then invoke_with_optional_key(context, :open_toc, key)
            when :quit_application then invoke_with_optional_key(context, :quit_application, key)
            when :quit_to_menu then invoke_with_optional_key(context, :quit_to_menu, key)
            when :read_confirm_or_sidebar then invoke_with_optional_key(context, :read_confirm_or_sidebar, key)
            when :read_scroll_down_or_sidebar then invoke_with_optional_key(context, :read_scroll_down_or_sidebar, key)
            when :read_scroll_up_or_sidebar then invoke_with_optional_key(context, :read_scroll_up_or_sidebar, key)
            when :read_space_or_sidebar_toggle then invoke_with_optional_key(context, :read_space_or_sidebar_toggle, key)
            when :rebuild_pagination then invoke_with_optional_key(context, :rebuild_pagination, key)
            when :show_help then invoke_with_optional_key(context, :show_help, key)
            when :toggle_page_numbering_mode then invoke_with_optional_key(context, :toggle_page_numbering_mode, key)
            when :toggle_view_mode then invoke_with_optional_key(context, :toggle_view_mode, key)
            else
              raise ContractMismatchError, "Unsupported reader gateway command: #{@command_symbol}"
            end
          end

          def invoke_with_optional_key(context, method_name, key)
            method = context.method(method_name)
            return method.call if method.arity.zero?

            method.call(key)
          rescue ArgumentError => e
            raise unless wrong_number_of_arguments?(e)

            method.call
          end

          def wrong_number_of_arguments?(error)
            error.message.include?('wrong number of arguments')
          end
        end
      end
    end
  end
end
