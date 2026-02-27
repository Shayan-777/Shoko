# frozen_string_literal: true

require_relative '../../core/ports/inbound/input_command_payload'

module Shoko
  module Adapters
    module Input
      # Generic command execution helpers used by the input system.
      module Commands
        module_function

        # Execute a command against the given context.
        # Supports multiple command types:
        # - Symbol: resolves to command_bus command and executes it
        # - Proc/Lambda: calls with (context, key) if arity 2, else with (key)
        # - Array [Symbol, *args]: resolves symbol via command_bus and passes args in params[:args]
        # - Command object (responds to #execute): calls command.execute(context, params)
        def execute(command, context, key = nil)
          payload = input_payload_for(key)

          case command
          when Symbol
            execute_symbol(command, context, payload)
          when Proc
            execute_proc(command, context, key)
          when Array
            sym, *args = command
            unless sym.is_a?(Symbol)
              log_command_error(context, 'command.contract_mismatch', command: command.inspect)
              return :error
            end

            execute_symbol(sym, context, payload.with(args: args.freeze))
          else
            execute_object(command, context, payload)
          end
        rescue ArgumentError => e
          log_command_error(context, 'command.invalid_payload',
                            command: command.class.name, error_class: e.class.name, error: e.message)
          :error
        rescue StandardError => e
          log_command_error(context, 'command.execution_error',
                            command: command.class.name, error_class: e.class.name, error: e.message)
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

        def execute_object(command, context, payload)
          unless executable_command?(command)
            log_command_error(context, 'command.contract_mismatch', command: command.class.name)
            return :error
          end

          command.execute(context, payload)
        end
        private_class_method :execute_object

        def execute_proc(command, context, key)
          arity = command.arity
          arity_abs = arity.abs
          return command.call(context, key) if arity_abs >= 2
          return command.call(key) if arity_abs >= 1

          command.call
        end
        private_class_method :execute_proc

        def executable_command?(command)
          return false if command.nil?

          command.method(:execute)
          true
        rescue NameError
          false
        end
        private_class_method :executable_command?

        def command_bus_for(context)
          return nil unless context

          context.command_bus
        rescue NoMethodError
          nil
        end
        private_class_method :command_bus_for

        def command_logger(context)
          return nil unless context

          context.command_logger
        rescue NoMethodError
          nil
        end
        private_class_method :command_logger

        def log_command_error(context, event, **metadata)
          logger = command_logger(context)
          return unless logger

          logger.error(event, **metadata.merge(context: context_name(context)))
        rescue NoMethodError, ArgumentError
          nil
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
