# frozen_string_literal: true

require_relative '../../application/use_cases/commands/application_commands'
require_relative '../../application/use_cases/commands/navigation_commands'
require_relative '../../application/use_cases/commands/sidebar_commands'
require_relative '../../application/use_cases/commands/conditional_navigation_commands'
require_relative '../../application/use_cases/commands/menu_commands'
require_relative '../../application/use_cases/commands/bookmark_commands'
require_relative '../../application/use_cases/commands/reader_commands'

module Shoko
  module Adapters::Input
    # Bridge to create Application commands for Input system usage.
    # Provides a clean interface for the Input system to use Application commands
    # while maintaining backward compatibility during the migration.
    class CommandBridge
      # Command registry mapping symbols to factory lambdas.
      # Each entry returns a new command instance when called.
      COMMAND_REGISTRY = {
        # Navigation commands
        next_page: -> { Application::Commands::NavigationCommand.new(:next_page) },
        prev_page: -> { Application::Commands::NavigationCommand.new(:prev_page) },
        next_chapter: -> { Application::Commands::NavigationCommand.new(:next_chapter) },
        prev_chapter: -> { Application::Commands::NavigationCommand.new(:prev_chapter) },
        scroll_up: -> { Application::Commands::NavigationCommandFactory.scroll_up },
        scroll_down: -> { Application::Commands::NavigationCommandFactory.scroll_down },
        go_to_start: -> { Application::Commands::NavigationCommand.new(:go_to_start) },
        go_to_end: -> { Application::Commands::NavigationCommand.new(:go_to_end) },

        # Application commands
        show_help: -> { Application::Commands::ApplicationCommand.new(:show_help) },
        open_toc: -> { Application::Commands::ApplicationCommand.new(:show_toc) },
        open_bookmarks: -> { Application::Commands::ApplicationCommand.new(:show_bookmarks) },
        open_annotations: -> { Application::Commands::ApplicationCommand.new(:show_annotations) },
        quit_to_menu: -> { Application::Commands::ApplicationCommand.new(:quit_to_menu) },
        add_bookmark: -> { Application::Commands::BookmarkCommandFactory.add_bookmark },

        # Conditional navigation commands
        conditional_up: -> { Application::Commands::ConditionalNavigationCommand.up_or_sidebar },
        conditional_down: -> { Application::Commands::ConditionalNavigationCommand.down_or_sidebar },
        conditional_select: -> { Application::Commands::ConditionalNavigationCommand.select_or_sidebar },

        # Direct sidebar commands
        sidebar_up: -> { Application::Commands::SidebarCommand.new(:up) },
        sidebar_down: -> { Application::Commands::SidebarCommand.new(:down) },
        sidebar_select: -> { Application::Commands::SidebarCommand.new(:select) },

        # Reader mode transitions
        exit_help: -> { Application::Commands::ReaderModeCommand.new(:exit_help) },
      }.freeze

      # Menu commands that follow the pattern MenuCommand.new(symbol)
      MENU_COMMAND_SYMBOLS = %i[
        menu_up menu_down menu_select menu_quit back_to_menu
        browse_up browse_down browse_select
        library_up library_down library_select
        settings_up settings_down settings_select
        start_search exit_search
        annotations_up annotations_down annotations_select annotations_edit annotations_delete
        annotation_detail_open annotation_detail_edit annotation_detail_delete annotation_detail_back
        toggle_view_mode cycle_line_spacing toggle_page_numbers toggle_page_numbering_mode
        toggle_highlight_quotes toggle_kitty_images wipe_cache
      ].freeze

      class << self
        # Create navigation commands for reader movement
        #
        # @param action [Symbol] Navigation action (:next_page, :prev_page, etc.)
        # @return [Application::Commands::NavigationCommand]
        def navigation_command(action)
          Application::Commands::NavigationCommand.new(action)
        end

        # Create application lifecycle commands
        #
        # @param action [Symbol] Application action (:quit, :switch_mode, etc.)
        # @return [Application::Commands::ApplicationCommand]
        def application_command(action)
          Application::Commands::ApplicationCommand.new(action)
        end

        # Create bookmark operation commands
        #
        # @param action [Symbol] Bookmark action (:add, :remove, :navigate, etc.)
        # @return [Application::Commands::BookmarkCommand]
        def bookmark_command(action)
          Application::Commands::BookmarkCommand.new(action)
        end

        # Create sidebar navigation commands
        #
        # @param action [Symbol] Sidebar action (:up, :down, :select)
        # @return [Application::Commands::SidebarCommand]
        def sidebar_command(action)
          Application::Commands::SidebarCommand.new(action)
        end

        # Create conditional navigation commands
        #
        # @param type [Symbol] Type of conditional navigation
        # @return [Application::Commands::ConditionalNavigationCommand]
        def conditional_navigation_command(type)
          case type
          when :up_or_sidebar then Application::Commands::ConditionalNavigationCommand.up_or_sidebar
          when :down_or_sidebar then Application::Commands::ConditionalNavigationCommand.down_or_sidebar
          when :select_or_sidebar then Application::Commands::ConditionalNavigationCommand.select_or_sidebar
          else
            raise ArgumentError, "Unknown conditional navigation type: #{type}"
          end
        end

        # Convert Input system symbols to appropriate Application commands
        # Uses a registry-based lookup for O(1) command resolution.
        #
        # @param symbol [Symbol] Input symbol
        # @param context [Object] Execution context (unused, kept for compatibility)
        # @return [Application::Commands::BaseCommand, nil] Command or nil if no mapping
        def symbol_to_command(symbol, _context = nil)
          # Check registry first (navigation, application, sidebar, conditional)
          factory = COMMAND_REGISTRY[symbol]
          return factory.call if factory

          # Check menu commands (all follow same pattern)
          return Application::Commands::MenuCommand.new(symbol) if MENU_COMMAND_SYMBOLS.include?(symbol)

          nil
        end

        # Check if a symbol can be converted to an Application command
        #
        # @param symbol [Symbol] Input symbol to check
        # @return [Boolean] True if symbol has Application command equivalent
        def command?(symbol)
          COMMAND_REGISTRY.key?(symbol) || MENU_COMMAND_SYMBOLS.include?(symbol)
        end
      end
    end
  end
end
