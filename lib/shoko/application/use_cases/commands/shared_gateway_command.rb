# frozen_string_literal: true

require_relative '../../../core/ports/inbound/reader_command_gateway'
require_relative '../../../core/ports/inbound/menu_command_gateway'
require_relative 'input_command_payload'

module Shoko
  module Application
    module UseCases
      module Commands
        # Explicit command for symbols shared across reader and menu gateways.
        class SharedGatewayCommand
          class InvalidPayloadError < StandardError; end
          class ContractMismatchError < StandardError; end

          SHARED_METHODS = %i[
            annotation_editor_backspace
            annotation_editor_cancel
            annotation_editor_enter
            annotation_editor_move_down
            annotation_editor_move_left
            annotation_editor_move_right
            annotation_editor_move_up
            annotation_editor_save
          ].freeze

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
            reader_gateway = context.is_a?(Shoko::Core::Ports::Inbound::ReaderCommandGateway)
            menu_gateway = context.is_a?(Shoko::Core::Ports::Inbound::MenuCommandGateway)
            return if reader_gateway || menu_gateway

            raise ContractMismatchError,
                  'Context must implement ReaderCommandGateway or MenuCommandGateway'
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
            when :annotation_editor_move_down then invoke_with_optional_key(context, :annotation_editor_move_down, key)
            when :annotation_editor_move_left then invoke_with_optional_key(context, :annotation_editor_move_left, key)
            when :annotation_editor_move_right then invoke_with_optional_key(context, :annotation_editor_move_right, key)
            when :annotation_editor_move_up then invoke_with_optional_key(context, :annotation_editor_move_up, key)
            when :annotation_editor_save then invoke_with_optional_key(context, :annotation_editor_save, key)
            else
              raise ContractMismatchError, "Unsupported shared gateway command: #{@command_symbol}"
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
