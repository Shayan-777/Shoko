# frozen_string_literal: true

module Shoko
  module Adapters::Input
    # Bridge to create commands for Input system usage.
    # This adapter delegates to the CommandPort for actual command creation,
    # maintaining clean hexagonal architecture boundaries.
    #
    # The command registry has been moved to CommandPortAdapter in the application layer.
    # This class now serves as a thin wrapper that the input system can use.
    class CommandBridge
      # Menu command symbols that are supported
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

      # Navigation and application command symbols
      STANDARD_COMMAND_SYMBOLS = %i[
        next_page prev_page next_chapter prev_chapter
        scroll_up scroll_down go_to_start go_to_end
        show_help open_toc open_bookmarks open_annotations quit_to_menu add_bookmark
        conditional_up conditional_down conditional_select conditional_space
        sidebar_up sidebar_down sidebar_select sidebar_toggle_toc
        exit_help
        annotation_editor_cancel annotation_editor_save annotation_editor_backspace annotation_editor_enter
        annotation_editor_move_left annotation_editor_move_right annotation_editor_move_up annotation_editor_move_down
      ].freeze

      class << self
        # Convert Input system symbols to commands via the CommandPort
        #
        # @param symbol [Symbol] Input symbol
        # @param context [Object] Execution context (must have access to command_port)
        # @return [Object, nil] Command or nil if no mapping
        def symbol_to_command(symbol, context = nil)
          command_port = resolve_command_port(context)
          return nil unless command_port

          command_port.build_command(symbol)
        end

        # Check if a symbol can be converted to a command
        #
        # @param symbol [Symbol] Input symbol to check
        # @return [Boolean] True if symbol has command equivalent
        def command?(symbol)
          STANDARD_COMMAND_SYMBOLS.include?(symbol) || MENU_COMMAND_SYMBOLS.include?(symbol)
        end

        private

        def resolve_command_port(context)
          return nil unless context

          # Try to get command_port from context's DI container
          if context.respond_to?(:resolve)
            context.resolve(:command_port)
          elsif context.respond_to?(:command_port)
            context.command_port
          elsif context.respond_to?(:container) && context.container.respond_to?(:resolve)
            context.container.resolve(:command_port)
          elsif context.respond_to?(:dependencies) && context.dependencies.respond_to?(:resolve)
            context.dependencies.resolve(:command_port)
          elsif context.respond_to?(:deps) && context.deps.respond_to?(:resolve)
            context.deps.resolve(:command_port)
          end
        rescue StandardError
          nil
        end
      end
    end
  end
end
