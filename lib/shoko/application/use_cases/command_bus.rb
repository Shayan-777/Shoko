# frozen_string_literal: true

require_relative '../../core/ports/inbound/command_bus'
require_relative '../../core/ports/inbound/intent_dispatch_context'
require_relative 'commands/navigation_commands'
require_relative 'commands/bookmark_commands'
require_relative 'commands/input_command_payload'
require_relative 'commands/reader/context_commands'
require_relative 'commands/menu/context_commands'
require_relative 'commands/shared/annotation_editor_command'

module Shoko
  module Application
    module UseCases
      # Inbound application command bus used by driving adapters.
      class CommandBus
        include Core::Ports::Inbound::CommandBus

        # Command namespace used by the registry factories.
        Commands = Shoko::Application::UseCases::Commands

        # Semantic application commands with explicit use-case behavior.
        SEMANTIC_COMMAND_REGISTRY = {
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

        READER_INTENT_COMMAND_REGISTRY = Commands::Reader::OverlayCommand.registry
                                         .merge(Commands::Reader::DictionaryCommand.registry)
                                         .merge(Commands::Reader::SearchCommand.registry)
                                         .merge(Commands::Reader::AnnotationEditorCommand.registry)
                                         .merge(Commands::Reader::LifecycleCommand.registry)
          .freeze

        MENU_INTENT_COMMAND_REGISTRY = Commands::Menu::NavigationCommand.registry
                                       .merge(Commands::Menu::BrowseCommand.registry)
                                       .merge(Commands::Menu::SearchCommand.registry)
                                       .merge(Commands::Menu::DownloadCommand.registry)
                                       .merge(Commands::Menu::DictionaryCommand.registry)
                                       .merge(Commands::Menu::AnnotationCommand.registry)
                                       .merge(Commands::Menu::SettingsCommand.registry)
                                       .merge(Commands::Menu::LifecycleCommand.registry)
          .freeze

        SHARED_INTENT_COMMAND_REGISTRY = Commands::Shared::AnnotationEditorCommand.registry.freeze
        SHARED_INTENT_SYMBOLS = SHARED_INTENT_COMMAND_REGISTRY.keys.freeze

        COMMAND_REGISTRY = begin
          reader_unique = READER_INTENT_COMMAND_REGISTRY.reject { |symbol, _| SHARED_INTENT_SYMBOLS.include?(symbol) }
          menu_unique = MENU_INTENT_COMMAND_REGISTRY.reject { |symbol, _| SHARED_INTENT_SYMBOLS.include?(symbol) }

          SEMANTIC_COMMAND_REGISTRY
            .merge(SHARED_INTENT_COMMAND_REGISTRY)
            .merge(reader_unique)
            .merge(menu_unique)
            .freeze
        end

        def initialize; end

        # Build a command object from a command symbol.
        #
        # @param command_symbol [Symbol] The command identifier.
        # @param _params [Hash] Optional parameters for the command.
        # @return [Object, nil] A command object that responds to #execute.
        def build_command(command_symbol, _params = {})
          factory = COMMAND_REGISTRY[command_symbol]
          factory&.call
        end

        # Execute a command directly by symbol.
        #
        # @param command_symbol [Symbol] The command identifier.
        # @param context [Object] The execution context.
        # @param params [Hash] Optional parameters for the command.
        # @return [Object, nil] The result of command execution.
        def execute_command(command_symbol, context, params = {})
          payload = normalize_payload(params)
          command = build_command(command_symbol, params)
          unless command
            log_command_error(context, 'command.unknown', command: command_symbol)
            return :error
          end

          result = command.execute(context, payload)
          result.nil? ? :handled : result
        rescue ArgumentError => e
          log_command_error(
            context,
            'command.invalid_payload',
            command: command_symbol,
            error_class: e.class.name,
            error: e.message
          )
          :error
        rescue Shoko::Error => e
          event = e.is_a?(Commands::BaseCommand::ValidationError) ? 'command.contract_mismatch' : 'command.execution_error'
          log_command_error(
            context,
            event,
            command: command_symbol,
            error_class: e.class.name,
            error: e.message
          )
          :error
        end

        # Check if a command exists.
        #
        # @param command_symbol [Symbol] The command identifier.
        # @return [Boolean] True if the command exists.
        def command_exists?(command_symbol)
          COMMAND_REGISTRY.key?(command_symbol)
        end

        private

        def normalize_payload(value)
          Commands::InputCommandPayload.from(value)
        end

        def log_command_error(context, event, **metadata)
          logger = command_logger(context)
          return unless logger

          logger.error(event, **metadata.merge(context: context_name(context)))
        end

        def command_logger(context)
          return nil unless context.is_a?(Shoko::Core::Ports::Inbound::IntentDispatchContext)

          context.command_logger
        end

        def context_name(context)
          context ? context.class.name : 'nil'
        end
      end
    end
  end
end
