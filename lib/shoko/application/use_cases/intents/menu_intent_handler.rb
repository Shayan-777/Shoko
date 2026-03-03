# frozen_string_literal: true

require_relative '../../../core/ports/inbound/menu_intent_handler'
require_relative '../../../core/ports/outbound/menu_intent_executor'

module Shoko
  module Application
    module UseCases
      module Intents
        # Application-level menu intent dispatcher.
        class MenuIntentHandler
          include Shoko::Core::Ports::Inbound::MenuIntentHandler

          Dependencies = Data.define(:intent_executor, :command_logger) do
            def validate!
              raise ArgumentError, 'Missing intent_executor dependency' if intent_executor.nil?
              raise ArgumentError, 'Missing command_logger dependency' if command_logger.nil?

              unless intent_executor.is_a?(Shoko::Core::Ports::Outbound::MenuIntentExecutor)
                raise ArgumentError, "intent_executor must implement #{Shoko::Core::Ports::Outbound::MenuIntentExecutor}"
              end

              self
            end
          end

          def initialize(deps:)
            dependencies = deps.validate!
            @intent_executor = dependencies.intent_executor
            @command_logger = dependencies.command_logger
          end

          def command_logger
            @command_logger
          end

          def handle_menu_intent(intent_symbol, payload = nil)
            intent = intent_symbol.to_sym
            raise ArgumentError, "Unsupported menu intent: #{intent_symbol}" unless INTENT_SYMBOLS.include?(intent)

            @intent_executor.execute(intent_symbol: intent, payload: payload)
          end
        end
      end
    end
  end
end
