# frozen_string_literal: true

require_relative '../base_command'
require_relative '../../../../core/ports/inbound/reader_command_contexts'

module Shoko
  module Application
    module UseCases
      module Commands
        module Reader
          # Reader overlay, popup, and display-mode actions.
          class OverlayCommand < Commands::BaseCommand
            SUPPORTED_INTENTS = %i[
              open_toc
              open_bookmarks
              open_annotations_tab
              open_annotations
              show_help
              toggle_view_mode
              increase_line_spacing
              decrease_line_spacing
              toggle_page_numbering_mode
              handle_popup_action_key
              handle_popup_cancel
              handle_popup_navigation
              help_exit_to_read
              read_confirm_or_sidebar
              read_scroll_down_or_sidebar
              read_scroll_up_or_sidebar
              read_space_or_sidebar_toggle
            ].freeze

            def self.registry
              SUPPORTED_INTENTS.to_h { |symbol| [symbol, -> { new(symbol) }] }.freeze
            end

            def initialize(intent_symbol)
              @intent_symbol = intent_symbol.to_sym
              super(name: "reader_overlay_#{@intent_symbol}", description: "Reader overlay #{@intent_symbol}")
            end

            def validate_context(context)
              super
              return if context.is_a?(Shoko::Core::Ports::Inbound::ReaderOverlayCommandContext)

              raise ValidationError.new(
                'Context must implement Core::Ports::Inbound::ReaderOverlayCommandContext',
                command_name: name
              )
            end

            protected

            def perform(context, params = {})
              key = params[:key]

              case @intent_symbol
              when :open_toc then context.open_toc
              when :open_bookmarks then context.open_bookmarks
              when :open_annotations_tab then context.open_annotations_tab
              when :open_annotations then context.open_annotations
              when :show_help then context.show_help
              when :toggle_view_mode then context.toggle_view_mode
              when :increase_line_spacing then context.increase_line_spacing
              when :decrease_line_spacing then context.decrease_line_spacing
              when :toggle_page_numbering_mode then context.toggle_page_numbering_mode
              when :handle_popup_action_key then context.handle_popup_action_key(key)
              when :handle_popup_cancel then context.handle_popup_cancel(key)
              when :handle_popup_navigation then context.handle_popup_navigation(key)
              when :help_exit_to_read then context.help_exit_to_read
              when :read_confirm_or_sidebar then context.read_confirm_or_sidebar(key)
              when :read_scroll_down_or_sidebar then context.read_scroll_down_or_sidebar(key)
              when :read_scroll_up_or_sidebar then context.read_scroll_up_or_sidebar(key)
              when :read_space_or_sidebar_toggle then context.read_space_or_sidebar_toggle(key)
              else
                raise ExecutionError.new("Unsupported reader overlay intent: #{@intent_symbol}", command_name: name)
              end

              @intent_symbol
            end
          end

          # Reader dictionary interaction commands.
          class DictionaryCommand < Commands::BaseCommand
            SUPPORTED_INTENTS = %i[
              dictionary_backspace
              dictionary_cancel
              dictionary_confirm
              dictionary_cycle_pair
              dictionary_cycle_result
              dictionary_insert_char_if_printable
              dictionary_scroll_down
              dictionary_scroll_up
              dictionary_swap_languages
              dictionary_toggle_fuzzy
            ].freeze

            def self.registry
              SUPPORTED_INTENTS.to_h { |symbol| [symbol, -> { new(symbol) }] }.freeze
            end

            def initialize(intent_symbol)
              @intent_symbol = intent_symbol.to_sym
              super(name: "reader_dictionary_#{@intent_symbol}", description: "Reader dictionary #{@intent_symbol}")
            end

            def validate_context(context)
              super
              return if context.is_a?(Shoko::Core::Ports::Inbound::ReaderDictionaryCommandContext)

              raise ValidationError.new(
                'Context must implement Core::Ports::Inbound::ReaderDictionaryCommandContext',
                command_name: name
              )
            end

            protected

            def perform(context, params = {})
              key = params[:key]

              case @intent_symbol
              when :dictionary_backspace then context.dictionary_backspace
              when :dictionary_cancel then context.dictionary_cancel
              when :dictionary_confirm then context.dictionary_confirm
              when :dictionary_cycle_pair then context.dictionary_cycle_pair
              when :dictionary_cycle_result then context.dictionary_cycle_result
              when :dictionary_insert_char_if_printable then context.dictionary_insert_char_if_printable(key)
              when :dictionary_scroll_down then context.dictionary_scroll_down
              when :dictionary_scroll_up then context.dictionary_scroll_up
              when :dictionary_swap_languages then context.dictionary_swap_languages
              when :dictionary_toggle_fuzzy then context.dictionary_toggle_fuzzy
              else
                raise ExecutionError.new("Unsupported reader dictionary intent: #{@intent_symbol}", command_name: name)
              end

              @intent_symbol
            end
          end

          # Reader in-book search commands.
          class SearchCommand < Commands::BaseCommand
            SUPPORTED_INTENTS = %i[
              open_in_book_search
              in_book_search_backspace
              in_book_search_cancel
              in_book_search_confirm
              in_book_search_down
              in_book_search_insert_char_if_printable
              in_book_search_up
            ].freeze

            def self.registry
              SUPPORTED_INTENTS.to_h { |symbol| [symbol, -> { new(symbol) }] }.freeze
            end

            def initialize(intent_symbol)
              @intent_symbol = intent_symbol.to_sym
              super(name: "reader_search_#{@intent_symbol}", description: "Reader search #{@intent_symbol}")
            end

            def validate_context(context)
              super
              return if context.is_a?(Shoko::Core::Ports::Inbound::ReaderSearchCommandContext)

              raise ValidationError.new(
                'Context must implement Core::Ports::Inbound::ReaderSearchCommandContext',
                command_name: name
              )
            end

            protected

            def perform(context, params = {})
              key = params[:key]

              case @intent_symbol
              when :open_in_book_search then context.open_in_book_search
              when :in_book_search_backspace then context.in_book_search_backspace
              when :in_book_search_cancel then context.in_book_search_cancel
              when :in_book_search_confirm then context.in_book_search_confirm
              when :in_book_search_down then context.in_book_search_down
              when :in_book_search_insert_char_if_printable then context.in_book_search_insert_char_if_printable(key)
              when :in_book_search_up then context.in_book_search_up
              else
                raise ExecutionError.new("Unsupported reader search intent: #{@intent_symbol}", command_name: name)
              end

              @intent_symbol
            end
          end

          # Reader-only annotation editor commands that are not shared with menu.
          class AnnotationEditorCommand < Commands::BaseCommand
            SUPPORTED_INTENTS = %i[
              annotation_editor_insert_char_if_printable
              annotation_editor_spellcheck
            ].freeze

            def self.registry
              SUPPORTED_INTENTS.to_h { |symbol| [symbol, -> { new(symbol) }] }.freeze
            end

            def initialize(intent_symbol)
              @intent_symbol = intent_symbol.to_sym
              super(name: "reader_annotation_editor_#{@intent_symbol}", description: "Reader annotation editor #{@intent_symbol}")
            end

            def validate_context(context)
              super
              return if context.is_a?(Shoko::Core::Ports::Inbound::ReaderAnnotationEditorCommandContext)

              raise ValidationError.new(
                'Context must implement Core::Ports::Inbound::ReaderAnnotationEditorCommandContext',
                command_name: name
              )
            end

            protected

            def perform(context, params = {})
              case @intent_symbol
              when :annotation_editor_insert_char_if_printable
                context.annotation_editor_insert_char_if_printable(params[:key])
              when :annotation_editor_spellcheck
                context.annotation_editor_spellcheck
              else
                raise ExecutionError.new("Unsupported reader annotation editor intent: #{@intent_symbol}", command_name: name)
              end

              @intent_symbol
            end
          end

          # Reader lifecycle and pagination maintenance commands.
          class LifecycleCommand < Commands::BaseCommand
            SUPPORTED_INTENTS = %i[
              invalidate_pagination_cache
              quit_application
              quit_to_menu
              rebuild_pagination
            ].freeze

            def self.registry
              SUPPORTED_INTENTS.to_h { |symbol| [symbol, -> { new(symbol) }] }.freeze
            end

            def initialize(intent_symbol)
              @intent_symbol = intent_symbol.to_sym
              super(name: "reader_lifecycle_#{@intent_symbol}", description: "Reader lifecycle #{@intent_symbol}")
            end

            def validate_context(context)
              super
              return if context.is_a?(Shoko::Core::Ports::Inbound::ReaderLifecycleCommandContext)

              raise ValidationError.new(
                'Context must implement Core::Ports::Inbound::ReaderLifecycleCommandContext',
                command_name: name
              )
            end

            protected

            def perform(context, _params = {})
              case @intent_symbol
              when :invalidate_pagination_cache then context.invalidate_pagination_cache
              when :quit_application then context.quit_application
              when :quit_to_menu then context.quit_to_menu
              when :rebuild_pagination then context.rebuild_pagination
              else
                raise ExecutionError.new("Unsupported reader lifecycle intent: #{@intent_symbol}", command_name: name)
              end

              @intent_symbol
            end
          end
        end
      end
    end
  end
end
