# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for command execution.
      # Adapters implementing this interface provide command creation and execution
      # without coupling input adapters to application-layer command classes.
      #
      # This allows the input layer to request commands by name/symbol without
      # knowing about specific command implementations in the application layer.
      #
      # @example Implementing this port
      #   class CommandPortAdapter
      #     include Shoko::Core::Ports::CommandPort
      #
      #     def build_command(command_symbol, params = {})
      #       case command_symbol
      #       when :next_page
      #         NavigationCommand.new(:next_page)
      #       # ...
      #       end
      #     end
      #   end
      module CommandPort
        # Build a command object from a command symbol/name
        #
        # @param command_symbol [Symbol] The command identifier
        # @param params [Hash] Optional parameters for the command
        # @return [Object, nil] A command object that responds to #execute, or nil if unknown
        def build_command(command_symbol, params = {})
          raise NotImplementedError, "#{self.class} must implement #build_command"
        end

        # Execute a command directly by symbol/name
        #
        # @param command_symbol [Symbol] The command identifier
        # @param context [Object] The execution context
        # @param params [Hash] Optional parameters for the command
        # @return [Object, nil] The result of command execution
        def execute_command(command_symbol, context, params = {})
          raise NotImplementedError, "#{self.class} must implement #execute_command"
        end

        # Check if a command exists
        #
        # @param command_symbol [Symbol] The command identifier
        # @return [Boolean] True if the command exists
        def command_exists?(command_symbol)
          raise NotImplementedError, "#{self.class} must implement #command_exists?"
        end
      end
    end
  end
end
