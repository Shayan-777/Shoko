# frozen_string_literal: true

require_relative '../base_command'
require_relative '../../../../core/ports/inbound/menu_command_contexts'

module Shoko
  module Application
    module UseCases
      module Commands
        module Menu
          # Menu navigation and mode-switch commands.
          class NavigationCommand < Commands::BaseCommand
            SUPPORTED_INTENTS = %i[
              menu_nav_up
              menu_nav_down
              menu_select
              menu_back_to_root
              switch_to_annotations_mode
              switch_to_browse
              switch_to_search
            ].freeze

            def self.registry
              SUPPORTED_INTENTS.to_h { |symbol| [symbol, -> { new(symbol) }] }.freeze
            end

            def initialize(intent_symbol)
              @intent_symbol = intent_symbol.to_sym
              super(name: "menu_navigation_#{@intent_symbol}", description: "Menu navigation #{@intent_symbol}")
            end

            def validate_context(context)
              super
              return if context.is_a?(Shoko::Core::Ports::Inbound::MenuNavigationCommandContext)

              raise ValidationError.new(
                'Context must implement Core::Ports::Inbound::MenuNavigationCommandContext',
                command_name: name
              )
            end

            protected

            def perform(context, _params = {})
              case @intent_symbol
              when :menu_nav_up then context.menu_nav_up
              when :menu_nav_down then context.menu_nav_down
              when :menu_select then context.menu_select
              when :menu_back_to_root then context.menu_back_to_root
              when :switch_to_annotations_mode then context.switch_to_annotations_mode
              when :switch_to_browse then context.switch_to_browse
              when :switch_to_search then context.switch_to_search
              else
                raise ExecutionError.new("Unsupported menu navigation intent: #{@intent_symbol}", command_name: name)
              end

              @intent_symbol
            end
          end

          # Menu browse and library selection commands.
          class BrowseCommand < Commands::BaseCommand
            SUPPORTED_INTENTS = %i[
              browse_down
              browse_up
              library_down
              library_select
              library_toggle_details
              library_up
              open_selected_book
            ].freeze

            def self.registry
              SUPPORTED_INTENTS.to_h { |symbol| [symbol, -> { new(symbol) }] }.freeze
            end

            def initialize(intent_symbol)
              @intent_symbol = intent_symbol.to_sym
              super(name: "menu_browse_#{@intent_symbol}", description: "Menu browse #{@intent_symbol}")
            end

            def validate_context(context)
              super
              return if context.is_a?(Shoko::Core::Ports::Inbound::MenuBrowseCommandContext)

              raise ValidationError.new(
                'Context must implement Core::Ports::Inbound::MenuBrowseCommandContext',
                command_name: name
              )
            end

            protected

            def perform(context, _params = {})
              case @intent_symbol
              when :browse_down then context.browse_down
              when :browse_up then context.browse_up
              when :library_down then context.library_down
              when :library_select then context.library_select
              when :library_toggle_details then context.library_toggle_details
              when :library_up then context.library_up
              when :open_selected_book then context.open_selected_book
              else
                raise ExecutionError.new("Unsupported menu browse intent: #{@intent_symbol}", command_name: name)
              end

              @intent_symbol
            end
          end

          # Menu search box editing commands.
          class SearchCommand < Commands::BaseCommand
            SUPPORTED_INTENTS = %i[
              search_backspace
              search_delete
              search_insert_char
            ].freeze

            def self.registry
              SUPPORTED_INTENTS.to_h { |symbol| [symbol, -> { new(symbol) }] }.freeze
            end

            def initialize(intent_symbol)
              @intent_symbol = intent_symbol.to_sym
              super(name: "menu_search_#{@intent_symbol}", description: "Menu search #{@intent_symbol}")
            end

            def validate_context(context)
              super
              return if context.is_a?(Shoko::Core::Ports::Inbound::MenuSearchCommandContext)

              raise ValidationError.new(
                'Context must implement Core::Ports::Inbound::MenuSearchCommandContext',
                command_name: name
              )
            end

            protected

            def perform(context, params = {})
              key = params[:key]

              case @intent_symbol
              when :search_backspace then context.search_backspace(key)
              when :search_delete then context.search_delete(key)
              when :search_insert_char then context.search_insert_char(key)
              else
                raise ExecutionError.new("Unsupported menu search intent: #{@intent_symbol}", command_name: name)
              end

              @intent_symbol
            end
          end

          # Menu download workflow commands.
          class DownloadCommand < Commands::BaseCommand
            SUPPORTED_INTENTS = %i[
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
            ].freeze

            def self.registry
              SUPPORTED_INTENTS.to_h { |symbol| [symbol, -> { new(symbol) }] }.freeze
            end

            def initialize(intent_symbol)
              @intent_symbol = intent_symbol.to_sym
              super(name: "menu_download_#{@intent_symbol}", description: "Menu download #{@intent_symbol}")
            end

            def validate_context(context)
              super
              return if context.is_a?(Shoko::Core::Ports::Inbound::MenuDownloadCommandContext)

              raise ValidationError.new(
                'Context must implement Core::Ports::Inbound::MenuDownloadCommandContext',
                command_name: name
              )
            end

            protected

            def perform(context, params = {})
              key = params[:key]

              case @intent_symbol
              when :download_confirm then context.download_confirm
              when :download_down then context.download_down
              when :download_exit_search then context.download_exit_search
              when :download_next_page then context.download_next_page
              when :download_prev_page then context.download_prev_page
              when :download_refresh then context.download_refresh
              when :download_search_backspace then context.download_search_backspace(key)
              when :download_search_delete then context.download_search_delete(key)
              when :download_search_insert_char then context.download_search_insert_char(key)
              when :download_start_search then context.download_start_search
              when :download_submit_search then context.download_submit_search
              when :download_up then context.download_up
              else
                raise ExecutionError.new("Unsupported menu download intent: #{@intent_symbol}", command_name: name)
              end

              @intent_symbol
            end
          end

          # Menu dictionary workflow commands.
          class DictionaryCommand < Commands::BaseCommand
            SUPPORTED_INTENTS = %i[
              dictionary_back
              dictionary_down
              dictionary_exit_search
              dictionary_refresh
              dictionary_search_backspace
              dictionary_search_delete
              dictionary_search_insert_char
              dictionary_select
              dictionary_start_search
              dictionary_submit_search
              dictionary_up
            ].freeze

            def self.registry
              SUPPORTED_INTENTS.to_h { |symbol| [symbol, -> { new(symbol) }] }.freeze
            end

            def initialize(intent_symbol)
              @intent_symbol = intent_symbol.to_sym
              super(name: "menu_dictionary_#{@intent_symbol}", description: "Menu dictionary #{@intent_symbol}")
            end

            def validate_context(context)
              super
              return if context.is_a?(Shoko::Core::Ports::Inbound::MenuDictionaryCommandContext)

              raise ValidationError.new(
                'Context must implement Core::Ports::Inbound::MenuDictionaryCommandContext',
                command_name: name
              )
            end

            protected

            def perform(context, params = {})
              key = params[:key]

              case @intent_symbol
              when :dictionary_back then context.dictionary_back
              when :dictionary_down then context.dictionary_down
              when :dictionary_exit_search then context.dictionary_exit_search
              when :dictionary_refresh then context.dictionary_refresh
              when :dictionary_search_backspace then context.dictionary_search_backspace(key)
              when :dictionary_search_delete then context.dictionary_search_delete(key)
              when :dictionary_search_insert_char then context.dictionary_search_insert_char(key)
              when :dictionary_select then context.dictionary_select
              when :dictionary_start_search then context.dictionary_start_search
              when :dictionary_submit_search then context.dictionary_submit_search
              when :dictionary_up then context.dictionary_up
              else
                raise ExecutionError.new("Unsupported menu dictionary intent: #{@intent_symbol}", command_name: name)
              end

              @intent_symbol
            end
          end

          # Menu annotation list and editor commands.
          class AnnotationCommand < Commands::BaseCommand
            SUPPORTED_INTENTS = %i[
              annotation_editor_insert_char
              annotations_down
              annotations_select
              annotations_up
              delete_selected_annotation
              open_selected_annotation
              open_selected_annotation_for_edit
            ].freeze

            def self.registry
              SUPPORTED_INTENTS.to_h { |symbol| [symbol, -> { new(symbol) }] }.freeze
            end

            def initialize(intent_symbol)
              @intent_symbol = intent_symbol.to_sym
              super(name: "menu_annotation_#{@intent_symbol}", description: "Menu annotation #{@intent_symbol}")
            end

            def validate_context(context)
              super
              return if context.is_a?(Shoko::Core::Ports::Inbound::MenuAnnotationCommandContext)

              raise ValidationError.new(
                'Context must implement Core::Ports::Inbound::MenuAnnotationCommandContext',
                command_name: name
              )
            end

            protected

            def perform(context, params = {})
              case @intent_symbol
              when :annotation_editor_insert_char
                context.annotation_editor_insert_char(params[:key])
              when :annotations_down
                context.annotations_down
              when :annotations_select
                context.annotations_select
              when :annotations_up
                context.annotations_up
              when :delete_selected_annotation
                context.delete_selected_annotation
              when :open_selected_annotation
                context.open_selected_annotation
              when :open_selected_annotation_for_edit
                context.open_selected_annotation_for_edit
              else
                raise ExecutionError.new("Unsupported menu annotation intent: #{@intent_symbol}", command_name: name)
              end

              @intent_symbol
            end
          end

          # Menu settings commands.
          class SettingsCommand < Commands::BaseCommand
            SUPPORTED_INTENTS = %i[
              settings_down
              settings_select
              settings_up
            ].freeze

            def self.registry
              SUPPORTED_INTENTS.to_h { |symbol| [symbol, -> { new(symbol) }] }.freeze
            end

            def initialize(intent_symbol)
              @intent_symbol = intent_symbol.to_sym
              super(name: "menu_settings_#{@intent_symbol}", description: "Menu settings #{@intent_symbol}")
            end

            def validate_context(context)
              super
              return if context.is_a?(Shoko::Core::Ports::Inbound::MenuSettingsCommandContext)

              raise ValidationError.new(
                'Context must implement Core::Ports::Inbound::MenuSettingsCommandContext',
                command_name: name
              )
            end

            protected

            def perform(context, _params = {})
              case @intent_symbol
              when :settings_down then context.settings_down
              when :settings_select then context.settings_select
              when :settings_up then context.settings_up
              else
                raise ExecutionError.new("Unsupported menu settings intent: #{@intent_symbol}", command_name: name)
              end

              @intent_symbol
            end
          end

          # Menu lifecycle commands.
          class LifecycleCommand < Commands::BaseCommand
            SUPPORTED_INTENTS = %i[
              menu_quit
            ].freeze

            def self.registry
              SUPPORTED_INTENTS.to_h { |symbol| [symbol, -> { new(symbol) }] }.freeze
            end

            def initialize(intent_symbol)
              @intent_symbol = intent_symbol.to_sym
              super(name: "menu_lifecycle_#{@intent_symbol}", description: "Menu lifecycle #{@intent_symbol}")
            end

            def validate_context(context)
              super
              return if context.is_a?(Shoko::Core::Ports::Inbound::MenuLifecycleCommandContext)

              raise ValidationError.new(
                'Context must implement Core::Ports::Inbound::MenuLifecycleCommandContext',
                command_name: name
              )
            end

            protected

            def perform(context, _params = {})
              case @intent_symbol
              when :menu_quit then context.menu_quit
              else
                raise ExecutionError.new("Unsupported menu lifecycle intent: #{@intent_symbol}", command_name: name)
              end

              @intent_symbol
            end
          end
        end
      end
    end
  end
end
