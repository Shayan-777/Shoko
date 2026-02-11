# frozen_string_literal: true

module Shoko
  module Adapters::Input
    # Bridge to create commands for Input system usage.
    # This adapter delegates command lookups/creation to the CommandPort.
    class CommandBridge
      class << self
        # Convert Input system symbols to commands via the CommandPort
        #
        # @param symbol [Symbol] Input symbol
        # @param context [Object] Execution context (must have access to command_port)
        # @return [Object, nil] Command or nil if no mapping
        def symbol_to_command(symbol, context = nil)
          command_port = resolve_command_port(context)
          return nil unless command_port

          return nil unless command_port.command_exists?(symbol)

          command_port.build_command(symbol)
        end

        # Check if a symbol can be converted to a command
        #
        # @param symbol [Symbol] Input symbol to check
        # @param context [Object] Execution context (must have access to command_port)
        # @return [Boolean] True if symbol has command equivalent
        def command?(symbol, context = nil)
          command_port = resolve_command_port(context)
          return false unless command_port

          command_port.command_exists?(symbol)
        end

        private

        def resolve_command_port(context)
          return nil unless context&.respond_to?(:command_port)

          context.command_port
        rescue StandardError
          nil
        end
      end
    end
  end
end
