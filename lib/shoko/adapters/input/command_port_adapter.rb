# frozen_string_literal: true

require_relative '../../application/ports/command_port'
require_relative '../../application/use_cases/commands/application_commands'
require_relative '../../application/use_cases/commands/navigation_commands'
require_relative '../../application/use_cases/commands/sidebar_commands'
require_relative '../../application/use_cases/commands/conditional_navigation_commands'
require_relative '../../application/use_cases/commands/menu_commands'
require_relative '../../application/use_cases/commands/bookmark_commands'
require_relative '../../application/use_cases/commands/reader_commands'
require_relative '../../application/use_cases/commands/reader_intent_commands'

module Shoko
  module Adapters::State
    # Application adapter implementing the CommandPort.
    # Creates and executes Application commands without exposing command classes to adapters.
    class CommandPortAdapter
      include Application::Ports::CommandPort

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

        # Application commands
        show_help: -> { Commands::ApplicationCommand.new(:show_help) },
        open_toc: -> { Commands::ApplicationCommand.new(:show_toc) },
        open_bookmarks: -> { Commands::ApplicationCommand.new(:show_bookmarks) },
        open_annotations: -> { Commands::ApplicationCommand.new(:show_annotations) },
        quit_to_menu: -> { Commands::ApplicationCommand.new(:quit_to_menu) },
        quit_application: -> { Commands::ApplicationCommand.new(:quit_application) },
        add_bookmark: -> { Commands::BookmarkCommandFactory.add_bookmark },

        # Conditional navigation commands
        conditional_up: -> { Commands::ConditionalNavigationCommand.up_or_sidebar },
        conditional_down: -> { Commands::ConditionalNavigationCommand.down_or_sidebar },
        conditional_select: -> { Commands::ConditionalNavigationCommand.select_or_sidebar },
        conditional_space: -> { Commands::ConditionalNavigationCommand.space_or_sidebar },

        # Direct sidebar commands
        sidebar_up: -> { Commands::SidebarCommand.new(:up) },
        sidebar_down: -> { Commands::SidebarCommand.new(:down) },
        sidebar_select: -> { Commands::SidebarCommand.new(:select) },
        sidebar_toggle_toc: -> { Commands::SidebarCommand.new(:toggle_toc) },

        # Reader mode transitions
        exit_help: -> { Commands::ReaderModeCommand.new(:exit_help) },

        # Annotation editor commands
        annotation_editor_cancel: -> { Commands::AnnotationEditorCommandFactory.cancel },
        annotation_editor_save: -> { Commands::AnnotationEditorCommandFactory.save },
        annotation_editor_backspace: -> { Commands::AnnotationEditorCommandFactory.backspace },
        annotation_editor_enter: -> { Commands::AnnotationEditorCommandFactory.enter },
        annotation_editor_move_left: -> { Commands::AnnotationEditorCommandFactory.move_left },
        annotation_editor_move_right: -> { Commands::AnnotationEditorCommandFactory.move_right },
        annotation_editor_move_up: -> { Commands::AnnotationEditorCommandFactory.move_up },
        annotation_editor_move_down: -> { Commands::AnnotationEditorCommandFactory.move_down },

        # Reader UI intent commands
        increase_line_spacing: -> { Commands::ReaderIntentCommand.new(:increase_line_spacing) },
        decrease_line_spacing: -> { Commands::ReaderIntentCommand.new(:decrease_line_spacing) },
        open_in_book_search: -> { Commands::ReaderIntentCommand.new(:open_in_book_search) },
        close_in_book_search: -> { Commands::ReaderIntentCommand.new(:close_in_book_search) },
        open_annotations_tab: -> { Commands::ReaderIntentCommand.new(:open_annotations_tab) },
        rebuild_pagination: -> { Commands::ReaderIntentCommand.new(:rebuild_pagination) },
        invalidate_pagination_cache: -> { Commands::ReaderIntentCommand.new(:invalidate_pagination_cache) },
        exit_popup_menu: -> { Commands::ReaderIntentCommand.new(:exit_popup_menu) },
        close_dictionary: -> { Commands::ReaderIntentCommand.new(:close_dictionary) },
        dictionary_scroll_up: -> { Commands::ReaderIntentCommand.new(:dictionary_scroll_up) },
        dictionary_scroll_down: -> { Commands::ReaderIntentCommand.new(:dictionary_scroll_down) },
        dictionary_toggle_fuzzy: -> { Commands::ReaderIntentCommand.new(:dictionary_toggle_fuzzy) },
        dictionary_cycle_result: -> { Commands::ReaderIntentCommand.new(:dictionary_cycle_result) },
        dictionary_cycle_pair: -> { Commands::ReaderIntentCommand.new(:dictionary_cycle_pair) },
        dictionary_insert_char: -> { Commands::ReaderIntentCommand.new(:dictionary_insert_char) },
        dictionary_backspace: -> { Commands::ReaderIntentCommand.new(:dictionary_backspace) },
        dictionary_confirm: -> { Commands::ReaderIntentCommand.new(:dictionary_confirm) },
        dictionary_cancel: -> { Commands::ReaderIntentCommand.new(:dictionary_cancel) },
        dictionary_tab: -> { Commands::ReaderIntentCommand.new(:dictionary_tab) },
        dictionary_swap_languages: -> { Commands::ReaderIntentCommand.new(:dictionary_swap_languages) },
        in_book_search_up: -> { Commands::ReaderIntentCommand.new(:in_book_search_up) },
        in_book_search_down: -> { Commands::ReaderIntentCommand.new(:in_book_search_down) },
        in_book_search_insert_char: -> { Commands::ReaderIntentCommand.new(:in_book_search_insert_char) },
        in_book_search_backspace: -> { Commands::ReaderIntentCommand.new(:in_book_search_backspace) },
        in_book_search_confirm: -> { Commands::ReaderIntentCommand.new(:in_book_search_confirm) },
        in_book_search_cancel: -> { Commands::ReaderIntentCommand.new(:in_book_search_cancel) },
      }.freeze

      # Menu commands that follow the pattern MenuCommand.new(symbol)
      MENU_COMMAND_SYMBOLS = %i[
        menu_up menu_down menu_select menu_quit back_to_menu
        browse_up browse_down browse_select
        library_up library_down library_select
        settings_up settings_down settings_select
        start_search exit_search
        dictionary_up dictionary_down dictionary_select dictionary_back dictionary_start_search
        dictionary_submit_search dictionary_exit_search dictionary_refresh
        download_up download_down download_confirm download_start_search download_submit_search
        download_exit_search download_next_page download_prev_page download_refresh
        annotations_up annotations_down annotations_select annotations_edit annotations_delete
        annotation_detail_open annotation_detail_edit annotation_detail_delete annotation_detail_back
        toggle_view_mode cycle_line_spacing toggle_page_numbers toggle_page_numbering_mode
        toggle_highlight_quotes toggle_kitty_images wipe_cache
      ].freeze

      def initialize
        # No state needed - this adapter just creates command objects
      end

      # Build a command object from a command symbol
      #
      # @param command_symbol [Symbol] The command identifier
      # @param params [Hash] Optional parameters for the command
      # @return [Object, nil] A command object that responds to #execute, or nil if unknown
      def build_command(command_symbol, _params = {})
        # Check registry first (navigation, application, sidebar, conditional)
        factory = COMMAND_REGISTRY[command_symbol]
        return factory.call if factory

        # Check for annotation editor insert_char command.
        # The factory creates a reusable command; the actual character is read
        # from params[:key] at execution time, not at construction time.
        if command_symbol == :annotation_editor_insert_char
          return Commands::AnnotationEditorCommandFactory.insert_char
        end

        # Check menu commands (all follow same pattern)
        return Commands::MenuCommand.new(command_symbol) if MENU_COMMAND_SYMBOLS.include?(command_symbol)

        nil
      end

      # Execute a command directly by symbol
      #
      # @param command_symbol [Symbol] The command identifier
      # @param context [Object] The execution context
      # @param params [Hash] Optional parameters for the command
      # @return [Object, nil] The result of command execution
      def execute_command(command_symbol, context, params = {})
        command = build_command(command_symbol, params)
        return nil unless command

        command.execute(context, params)
      end

      # Check if a command exists
      #
      # @param command_symbol [Symbol] The command identifier
      # @return [Boolean] True if the command exists
      def command_exists?(command_symbol)
        COMMAND_REGISTRY.key?(command_symbol) ||
          MENU_COMMAND_SYMBOLS.include?(command_symbol) ||
          command_symbol == :annotation_editor_insert_char
      end
    end
  end
end
