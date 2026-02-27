# frozen_string_literal: true

require_relative '../../../core/ports/inbound/menu_command_gateway'
require_relative 'input_command_payload'

module Shoko
  module Application
    module UseCases
      module Commands
        # Explicit gateway command dispatch for menu-bound input symbols.
        class MenuGatewayCommand
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
            return if context.is_a?(Shoko::Core::Ports::Inbound::MenuCommandGateway)

            raise ContractMismatchError,
                  "Context must implement #{Shoko::Core::Ports::Inbound::MenuCommandGateway}"
          end

          def normalize_payload(payload)
            InputCommandPayload.from(payload)
          rescue ArgumentError => e
            raise InvalidPayloadError, e.message
          end

          def dispatch(context, key)
            case @command_symbol
            when :annotation_editor_backspace then context.annotation_editor_backspace(key)
            when :annotation_editor_cancel then context.annotation_editor_cancel(key)
            when :annotation_editor_enter then context.annotation_editor_enter(key)
            when :annotation_editor_insert_char then context.annotation_editor_insert_char(key)
            when :annotation_editor_move_down then context.annotation_editor_move_down(key)
            when :annotation_editor_move_left then context.annotation_editor_move_left(key)
            when :annotation_editor_move_right then context.annotation_editor_move_right(key)
            when :annotation_editor_move_up then context.annotation_editor_move_up(key)
            when :annotation_editor_save then context.annotation_editor_save(key)
            when :annotations_down then context.annotations_down
            when :annotations_select then context.annotations_select
            when :annotations_up then context.annotations_up
            when :browse_down then context.browse_down(key)
            when :browse_up then context.browse_up(key)
            when :delete_selected_annotation then context.delete_selected_annotation
            when :dictionary_back then context.dictionary_back
            when :dictionary_down then context.dictionary_down
            when :dictionary_exit_search then context.dictionary_exit_search
            when :dictionary_refresh then context.dictionary_refresh
            when :dictionary_search_backspace then context.dictionary_search_backspace(key)
            when :dictionary_search_delete then context.dictionary_search_delete(key)
            when :dictionary_search_insert_char then context.dictionary_search_insert_char(key)
            when :dictionary_select then context.dictionary_select
            when :dictionary_start_search then context.dictionary_start_search
            when :dictionary_submit_search then context.dictionary_submit_search
            when :dictionary_up then context.dictionary_up
            when :download_confirm then context.download_confirm
            when :download_down then context.download_down
            when :download_exit_search then context.download_exit_search
            when :download_next_page then context.download_next_page
            when :download_prev_page then context.download_prev_page
            when :download_refresh then context.download_refresh
            when :download_search_backspace then context.download_search_backspace(key)
            when :download_search_delete then context.download_search_delete(key)
            when :download_search_insert_char then context.download_search_insert_char(key)
            when :download_start_search then context.download_start_search
            when :download_submit_search then context.download_submit_search
            when :download_up then context.download_up
            when :library_down then context.library_down
            when :library_select then context.library_select
            when :library_up then context.library_up
            when :menu_back_to_root then context.menu_back_to_root(key)
            when :menu_nav_down then context.menu_nav_down(key)
            when :menu_nav_up then context.menu_nav_up(key)
            when :menu_quit then context.menu_quit(key)
            when :menu_select then context.menu_select(key)
            when :open_selected_annotation then context.open_selected_annotation
            when :open_selected_annotation_for_edit then context.open_selected_annotation_for_edit
            when :open_selected_book then context.open_selected_book
            when :search_backspace then context.search_backspace(key)
            when :search_delete then context.search_delete(key)
            when :search_insert_char then context.search_insert_char(key)
            when :settings_down then context.settings_down(key)
            when :settings_select then context.settings_select(key)
            when :settings_up then context.settings_up(key)
            when :switch_to_annotations_mode then context.switch_to_annotations_mode(key)
            when :switch_to_browse then context.switch_to_browse
            when :switch_to_search then context.switch_to_search
            else
              raise ContractMismatchError, "Unsupported menu gateway command: #{@command_symbol}"
            end
          end
        end
      end
    end
  end
end
