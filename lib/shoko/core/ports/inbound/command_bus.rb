# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Inbound
        # Inbound application boundary for command dispatching.
        module CommandBus
          # Build a command object from a command symbol/name.
          #
          # @param command_symbol [Symbol] The command identifier.
          # @param params [Object] Optional command payload.
          # @return [Object, nil] Command object responding to #execute, or nil.
          def build_command(command_symbol, params = {})
            raise NotImplementedError, "#{self.class} must implement #build_command"
          end

          # Execute a command by symbol/name against a context.
          #
          # @param command_symbol [Symbol] The command identifier.
          # @param context [Object] Command execution context.
          # @param params [Object] Optional typed command payload.
          # @return [Object] Execution result.
          def execute_command(command_symbol, context, params = {})
            raise NotImplementedError, "#{self.class} must implement #execute_command"
          end

          # Check if a command symbol is registered.
          #
          # @param command_symbol [Symbol] The command identifier.
          # @return [Boolean]
          def command_exists?(command_symbol)
            raise NotImplementedError, "#{self.class} must implement #command_exists?"
          end
        end
      end
    end
  end
end
