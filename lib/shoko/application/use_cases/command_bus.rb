# frozen_string_literal: true

require_relative '../../core/ports/inbound/command_bus'
require_relative 'commands/navigation_commands'
require_relative 'commands/bookmark_commands'
require_relative 'commands/context_method_command'

module Shoko
  module Application
    module UseCases
      # Inbound application command bus used by driving adapters.
      class CommandBus
        include Core::Ports::Inbound::CommandBus

        # Command namespace used by the registry factories.
        Commands = Shoko::Application::UseCases::Commands

        # Command registry mapping symbols to factory lambdas.
        # Each entry returns a new command instance when called.
        COMMAND_REGISTRY = {
          # Navigation commands
          next_page: -> { Commands::NavigationCommand.new(:next_page) },
          prev_page: -> { Commands::NavigationCommand.new(:prev_page) },
          next_chapter: -> { Commands::NavigationCommand.new(:next_chapter) },
          prev_chapter: -> { Commands::NavigationCommand.new(:prev_chapter) },
          scroll_up: -> { Commands::NavigationCommandFactory.scroll_up },
          scroll_down: -> { Commands::NavigationCommandFactory.scroll_down },
          go_to_start: -> { Commands::NavigationCommand.new(:go_to_start) },
          go_to_end: -> { Commands::NavigationCommand.new(:go_to_end) },

          # Bookmark commands
          add_bookmark: -> { Commands::BookmarkCommandFactory.add_bookmark },
        }.freeze

        def initialize; end

        # Build a command object from a command symbol.
        #
        # @param command_symbol [Symbol] The command identifier.
        # @param _params [Hash] Optional parameters for the command.
        # @return [Object, nil] A command object that responds to #execute, or nil if unknown.
        def build_command(command_symbol, _params = {})
          factory = COMMAND_REGISTRY[command_symbol]
          return factory.call if factory

          Commands::ContextMethodCommand.new(command_symbol)
        end

        # Execute a command directly by symbol.
        #
        # @param command_symbol [Symbol] The command identifier.
        # @param context [Object] The execution context.
        # @param params [Hash] Optional parameters for the command.
        # @return [Object, nil] The result of command execution.
        def execute_command(command_symbol, context, params = {})
          command = build_command(command_symbol, params)
          return nil unless command

          command.execute(context, params)
        end

        # Check if a command exists.
        #
        # @param command_symbol [Symbol] The command identifier.
        # @return [Boolean] True if the command exists.
        def command_exists?(command_symbol)
          COMMAND_REGISTRY.key?(command_symbol) || context_method_symbol?(command_symbol)
        end

        private

        def context_method_symbol?(command_symbol)
          command_symbol.is_a?(Symbol) && command_symbol.to_s.match?(/\A[a-z_][a-z0-9_]*\z/)
        end
      end
    end
  end
end
