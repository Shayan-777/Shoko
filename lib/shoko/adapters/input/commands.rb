# frozen_string_literal: true

require_relative 'command_bridge'

module Shoko
  module Adapters::Input
    # Generic command execution helpers used by the input system.
    module Commands
      module_function

      # Execute a command against the given context.
      # Supports multiple command types:
      # - Symbol: calls context.public_send(symbol, key) if arity allows, else without args
      # - Proc/Lambda: calls with (context, key) if arity 2, else with (key)
      # - Array [Symbol, *args]: calls method with args splat
      # - Command object (responds to #execute): calls command.execute(context, params)
      def execute(command, context, key = nil)
        # Check for command objects first (duck typing - must respond to :execute)
        if command.respond_to?(:execute) && !command.is_a?(Symbol) && !command.is_a?(Proc)
          params = { key: key, triggered_by: :input }
          return command.execute(context, params)
        end

        case command
        when Symbol
          # Route all symbols through the command bridge
          if CommandBridge.command?(command)
            mapped_command = CommandBridge.symbol_to_command(command, context)
            return :pass unless mapped_command

            execute(mapped_command, context, key)
          else
            execute_symbol(command, context, key)
          end
        when Proc
          ar = command.arity
          ar_abs = ar.abs
          return command.call(context, key) if ar_abs >= 2
          return command.call(key) if ar_abs >= 1

          command.call
        when Array
          sym, *args = command
          return :pass unless sym.is_a?(Symbol) && context.respond_to?(sym)

          context.public_send(sym, *args)
        else
          :pass
        end
      end

      def execute_symbol(command, context, key)
        return :pass unless context.respond_to?(command)

        method = context.method(command)
        return context.public_send(command) if method.arity.zero?

        context.public_send(command, key)
      end
    end
  end
end
