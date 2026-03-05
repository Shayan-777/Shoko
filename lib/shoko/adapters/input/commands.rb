# frozen_string_literal: true

require_relative '../../core/ports/inbound/input_command_payload'
require_relative '../../core/ports/inbound/intent_dispatch_context'

module Shoko
  module Adapters
    module Input
      # Generic command execution helpers used by the input system.
      module Commands
        module_function

        # Execute a command against the given context.
        # Command bindings are symbol-only and always flow through the command bus.
        def execute(command_symbol, context, key = nil)
          unless command_symbol.is_a?(Symbol)
            log_command_error(context, 'command.contract_mismatch', command: command_symbol.inspect)
            return :error
          end

          payload = input_payload_for(key)
          execute_symbol(command_symbol, context, payload)
        rescue ArgumentError => e
          log_command_error(context, 'command.invalid_payload',
                            command: command_symbol, error_class: e.class.name, error: e.message)
          :error
        rescue Shoko::Error => e
          log_command_error(context, 'command.execution_error',
                            command: command_symbol, error_class: e.class.name, error: e.message)
          :error
        end

        def input_payload_for(key)
          Shoko::Core::Ports::Inbound::InputCommandPayload.new(
            key: key,
            triggered_by: :input,
            args: [].freeze,
            metadata: {}.freeze,
            key_provided: !key.nil?
          )
        end
        private_class_method :input_payload_for

        def execute_symbol(symbol, context, payload)
          command_bus = command_bus_for(context)
          unless command_bus
            log_command_error(context, 'command.contract_mismatch', command: symbol, reason: 'missing_command_bus')
            return :error
          end

          command_bus.execute_command(symbol, context, payload)
        end
        private_class_method :execute_symbol

        def command_bus_for(context)
          return nil unless context.is_a?(Shoko::Core::Ports::Inbound::IntentDispatchContext)

          context.command_bus
        end
        private_class_method :command_bus_for

        def command_logger(context)
          return nil unless context.is_a?(Shoko::Core::Ports::Inbound::IntentDispatchContext)

          context.command_logger
        end
        private_class_method :command_logger

        def log_command_error(context, event, **metadata)
          logger = command_logger(context)
          return unless logger

          logger.error(event, **metadata.merge(context: context_name(context)))
        end
        private_class_method :log_command_error

        def context_name(context)
          context ? context.class.name : 'nil'
        end
        private_class_method :context_name
      end
    end
  end
end
