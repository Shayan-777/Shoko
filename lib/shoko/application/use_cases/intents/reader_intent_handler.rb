# frozen_string_literal: true

require_relative '../../../core/ports/inbound/reader_intent_handler'
require_relative '../../../core/ports/outbound/reader_intent_executor'

module Shoko
  module Application
    module UseCases
      module Intents
        # Application-level reader intent dispatcher.
        class ReaderIntentHandler
          include Shoko::Core::Ports::Inbound::ReaderIntentHandler

          Dependencies = Data.define(:intent_executor, :command_logger) do
            def validate!
              raise ArgumentError, 'Missing intent_executor dependency' if intent_executor.nil?
              raise ArgumentError, 'Missing command_logger dependency' if command_logger.nil?

              unless intent_executor.is_a?(Shoko::Core::Ports::Outbound::ReaderIntentExecutor)
                raise ArgumentError, "intent_executor must implement #{Shoko::Core::Ports::Outbound::ReaderIntentExecutor}"
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

          def handle_reader_intent(intent_symbol, payload = nil)
            intent = intent_symbol.to_sym
            raise ArgumentError, "Unsupported reader intent: #{intent_symbol}" unless INTENT_SYMBOLS.include?(intent)

            @intent_executor.execute(intent_symbol: intent, payload: payload)
          end
        end
      end
    end
  end
end
