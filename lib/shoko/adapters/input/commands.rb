# frozen_string_literal: true

module Shoko
  module Adapters::Input
    # Generic command execution helpers used by the input system.
    module Commands
      module_function

      # Execute a command against the given context.
      # Supports multiple command types:
      # - Symbol: resolves to command_port command and executes it
      # - Proc/Lambda: calls with (context, key) if arity 2, else with (key)
      # - Array [Symbol, *args]: resolves symbol via command_port and passes args in params[:args]
      # - Command object (responds to #execute): calls command.execute(context, params)
      def execute(command, context, key = nil)
        if command.respond_to?(:execute) && !command.is_a?(Symbol) && !command.is_a?(Proc)
          params = { key: key, triggered_by: :input }
          return command.execute(context, params)
        end

        case command
        when Symbol
          mapped_command = build_command(context, command)
          return :pass unless mapped_command

          mapped_command.execute(context, key: key, triggered_by: :input)
        when Proc
          ar = command.arity
          ar_abs = ar.abs
          return command.call(context, key) if ar_abs >= 2
          return command.call(key) if ar_abs >= 1

          command.call
        when Array
          sym, *args = command
          return :pass unless sym.is_a?(Symbol)

          mapped_command = build_command(context, sym)
          return :pass unless mapped_command

          mapped_command.execute(context, key: key, triggered_by: :input, args: args)
        else
          :pass
        end
      end

      def build_command(context, symbol)
        return nil unless context

        command_port = context.command_port
        return nil unless command_port&.command_exists?(symbol)

        command_port.build_command(symbol)
      rescue StandardError
        nil
      end
      private_class_method :build_command
    end
  end
end
