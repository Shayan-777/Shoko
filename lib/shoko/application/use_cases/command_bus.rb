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

        # Explicitly allowed passthrough actions that dispatch to the runtime context.
        # This keeps adapter-driven controller actions whitelisted and auditable.
        PASSTHROUGH_COMMAND_SYMBOLS = %i[
          annotation_editor_backspace
          annotation_editor_cancel
          annotation_editor_enter
          annotation_editor_insert_char
          annotation_editor_insert_char_if_printable
          annotation_editor_move_down
          annotation_editor_move_left
          annotation_editor_move_right
          annotation_editor_move_up
          annotation_editor_save
          annotations_down
          annotations_select
          annotations_up
          browse_down
          browse_up
          decrease_line_spacing
          delete_selected_annotation
          dictionary_back
          dictionary_backspace
          dictionary_cancel
          dictionary_confirm
          dictionary_cycle_pair
          dictionary_cycle_result
          dictionary_down
          dictionary_exit_search
          dictionary_insert_char_if_printable
          dictionary_refresh
          dictionary_scroll_down
          dictionary_scroll_up
          dictionary_search_backspace
          dictionary_search_delete
          dictionary_search_insert_char
          dictionary_select
          dictionary_start_search
          dictionary_submit_search
          dictionary_swap_languages
          dictionary_toggle_fuzzy
          dictionary_up
          download_confirm
          download_down
          download_exit_search
          download_next_page
          download_prev_page
          download_refresh
          download_search_backspace
          download_search_delete
          download_search_insert_char
          download_start_search
          download_submit_search
          download_up
          handle_popup_action_key
          handle_popup_cancel
          handle_popup_navigation
          help_exit_to_read
          in_book_search_backspace
          in_book_search_cancel
          in_book_search_confirm
          in_book_search_down
          in_book_search_insert_char_if_printable
          in_book_search_up
          increase_line_spacing
          invalidate_pagination_cache
          library_down
          library_select
          library_up
          menu_back_to_root
          menu_nav_down
          menu_nav_up
          menu_quit
          menu_select
          open_annotations
          open_annotations_tab
          open_bookmarks
          open_in_book_search
          open_selected_annotation
          open_selected_annotation_for_edit
          open_selected_book
          open_toc
          quit_application
          quit_to_menu
          read_confirm_or_sidebar
          read_scroll_down_or_sidebar
          read_scroll_up_or_sidebar
          read_space_or_sidebar_toggle
          rebuild_pagination
          search_backspace
          search_delete
          search_insert_char
          settings_down
          settings_select
          settings_up
          show_help
          switch_to_annotations_mode
          switch_to_browse
          switch_to_search
          toggle_page_numbering_mode
          toggle_view_mode
        ].freeze

        # Full command registry mapping symbols to command factories.
        COMMAND_REGISTRY = begin
          registry = SEMANTIC_COMMAND_REGISTRY.dup
          PASSTHROUGH_COMMAND_SYMBOLS.each do |symbol|
            registry[symbol] ||= -> { Commands::ContextMethodCommand.new(symbol) }
          end
          registry.freeze
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
          command = build_command(command_symbol, params)
          return nil unless command

          command.execute(context, params)
        end

        # Check if a command exists.
        #
        # @param command_symbol [Symbol] The command identifier.
        # @return [Boolean] True if the command exists.
        def command_exists?(command_symbol)
          COMMAND_REGISTRY.key?(command_symbol)
        end
      end
    end
  end
end
