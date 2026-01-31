# frozen_string_literal: true

require_relative 'base_command'

module Shoko
  module Application
    module Commands
      # Application-level commands for mode switching and system control.
      class ApplicationCommand < BaseCommand
        def initialize(action, name: nil, description: nil)
          @action = action
          super(
            name: name || "app_#{action}",
            description: description || "Application #{action.to_s.tr('_', ' ')}"
          )
        end

        protected

        def perform(context, _params = {})
          case @action
          when :quit_to_menu
            handle_quit_to_menu(context)
          when :quit_application
            handle_quit_application(context)
          when :toggle_view_mode
            handle_toggle_view_mode(context)
          when :show_help
            handle_show_help(context)
          when :show_toc
            handle_show_toc(context)
          when :show_bookmarks
            handle_show_bookmarks(context)
          when :show_annotations
            handle_show_annotations(context)
          else
            raise ExecutionError.new("Unknown application action: #{@action}", command_name: name)
          end

          @action
        end

        private

        def handle_quit_to_menu(context)
          controller = context_accessor(context, :state_controller)
          if controller.respond_to?(:quit_to_menu)
            controller.quit_to_menu
          else
            context.state&.dispatch(Application::Actions::QuitToMenuAction.new)
          end
        end

        def handle_quit_application(context)
          controller = context_accessor(context, :state_controller)
          if controller.respond_to?(:quit_application)
            controller.quit_application
            return
          end

          handle_quit_to_menu(context)
          force_cleanup(context)
          Kernel.exit(0)
        end

        def handle_toggle_view_mode(context)
          controller = context_accessor(context, :ui_controller)
          if controller.respond_to?(:toggle_view_mode)
            controller.toggle_view_mode
          else
            context.state&.dispatch(Application::Actions::ToggleViewModeAction.new)
          end
        end

        def handle_show_help(context)
          controller = context_accessor(context, :ui_controller)
          if controller.respond_to?(:show_help)
            controller.show_help
          else
            context.state&.set(%i[reader mode], :help)
          end
        end

        def handle_show_toc(context)
          controller = context_accessor(context, :ui_controller)
          controller&.open_toc if controller.respond_to?(:open_toc)
        end

        def handle_show_bookmarks(context)
          controller = context_accessor(context, :ui_controller)
          controller&.open_bookmarks if controller.respond_to?(:open_bookmarks)
        end

        def handle_show_annotations(context)
          controller = context_accessor(context, :ui_controller)
          controller&.open_annotations if controller.respond_to?(:open_annotations)
        end

        def context_accessor(context, method)
          context.respond_to?(method) ? context.public_send(method) : nil
        rescue StandardError
          nil
        end

        def force_cleanup(context)
          terminal = context_accessor(context, :terminal_service)
          return unless terminal

          if terminal.respond_to?(:force_cleanup)
            terminal.force_cleanup
          elsif terminal.respond_to?(:cleanup)
            terminal.cleanup
          end
        end
      end

      # Command that switches the reader into a specific UI mode.
      class ModeCommand < BaseCommand
        def initialize(mode, name: nil, description: nil)
          @mode = mode
          super(
            name: name || "mode_#{mode}",
            description: description || "Switch to #{mode} mode"
          )
        end

        def validate_parameters(params)
          super

          valid_modes = %i[read help search]
          return if valid_modes.include?(@mode)

          raise ValidationError.new("Mode must be one of #{valid_modes}", command_name: name)
        end

        protected

        def perform(context, _params = {})
          context.state.set(%i[reader mode], @mode)

          @mode
        end
      end

      # Factory methods for common application commands
      module ApplicationCommandFactory
        def self.quit_to_menu
          ApplicationCommand.new(:quit_to_menu)
        end

        def self.quit_application
          ApplicationCommand.new(:quit_application)
        end

        def self.toggle_view_mode
          ApplicationCommand.new(:toggle_view_mode)
        end

        def self.show_help
          ApplicationCommand.new(:show_help)
        end

        def self.show_toc
          ApplicationCommand.new(:show_toc)
        end

        def self.show_bookmarks
          ApplicationCommand.new(:show_bookmarks)
        end

        def self.show_annotations
          ApplicationCommand.new(:show_annotations)
        end

        def self.switch_to_mode(mode)
          ModeCommand.new(mode)
        end
      end
    end
  end
end
