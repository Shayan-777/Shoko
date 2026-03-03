# frozen_string_literal: true

require_relative '../../../core/ports/inbound/reader_intent_handler'
require_relative '../../../core/ports/inbound/menu_intent_handler'
require_relative '../../../core/ports/inbound/intent_dispatch_context'
require_relative 'input_command_payload'

module Shoko
  module Application
    module UseCases
      module Commands
        # Explicit command for symbols shared across reader and menu intents.
        class SharedIntentCommand
          class InvalidPayloadError < StandardError; end
          class ContractMismatchError < StandardError; end

          def initialize(intent_symbol)
            @intent_symbol = intent_symbol.to_sym
          end

          def execute(context, payload = nil)
            normalized_payload = normalize_payload(payload)
            result = dispatch(context, normalized_payload)
            result.nil? ? :handled : result
          end

          private

          def normalize_payload(payload)
            InputCommandPayload.from(payload)
          rescue ArgumentError => e
            raise InvalidPayloadError, e.message
          end

          def dispatch(context, normalized_payload)
            unless context.is_a?(Shoko::Core::Ports::Inbound::IntentDispatchContext)
              raise ContractMismatchError,
                    "Context must implement #{Shoko::Core::Ports::Inbound::IntentDispatchContext}"
            end

            handler = context.intent_handler
            if handler.is_a?(Shoko::Core::Ports::Inbound::ReaderIntentHandler)
              handler.handle_reader_intent(@intent_symbol, normalized_payload)
            elsif handler.is_a?(Shoko::Core::Ports::Inbound::MenuIntentHandler)
              handler.handle_menu_intent(@intent_symbol, normalized_payload)
            else
              raise ContractMismatchError,
                    'Context intent_handler must implement ReaderIntentHandler or MenuIntentHandler'
            end
          end
        end
      end
    end
  end
end
