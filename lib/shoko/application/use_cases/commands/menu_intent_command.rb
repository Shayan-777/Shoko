# frozen_string_literal: true

require_relative '../../../core/ports/inbound/menu_intent_handler'
require_relative '../../../core/ports/inbound/intent_dispatch_context'
require_relative 'input_command_payload'

module Shoko
  module Application
    module UseCases
      module Commands
        # Explicit intent command dispatch for menu-bound input symbols.
        class MenuIntentCommand
          class InvalidPayloadError < StandardError; end
          class ContractMismatchError < StandardError; end

          def initialize(intent_symbol)
            @intent_symbol = intent_symbol.to_sym
          end

          def execute(context, payload = nil)
            handler = resolve_handler(context)
            normalized_payload = normalize_payload(payload)
            result = handler.handle_menu_intent(@intent_symbol, normalized_payload)
            result.nil? ? :handled : result
          end

          private

          def resolve_handler(context)
            unless context.is_a?(Shoko::Core::Ports::Inbound::IntentDispatchContext)
              raise ContractMismatchError,
                    "Context must implement #{Shoko::Core::Ports::Inbound::IntentDispatchContext}"
            end

            handler = context.intent_handler
            return handler if handler.is_a?(Shoko::Core::Ports::Inbound::MenuIntentHandler)

            raise ContractMismatchError,
                  "Context intent_handler must implement #{Shoko::Core::Ports::Inbound::MenuIntentHandler}"
          end

          def normalize_payload(payload)
            InputCommandPayload.from(payload)
          rescue ArgumentError => e
            raise InvalidPayloadError, e.message
          end
        end
      end
    end
  end
end
