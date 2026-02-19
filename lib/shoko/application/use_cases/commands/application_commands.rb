# frozen_string_literal: true

require_relative 'base_command'

module Shoko
  module Application
    module UseCases
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
            context.state_controller.quit_to_menu
          end

          def handle_quit_application(context)
            context.state_controller.quit_application
          end

          def handle_toggle_view_mode(context)
            context.ui_controller.toggle_view_mode
          end

          def handle_show_help(context)
            context.ui_controller.show_help
          end

          def handle_show_toc(context)
            context.ui_controller.open_toc
          end

          def handle_show_bookmarks(context)
            context.ui_controller.open_bookmarks
          end

          def handle_show_annotations(context)
            context.ui_controller.open_annotations
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
            writer = resolve_state_writer(context)
            return :pass unless writer

            writer.update_reader(mode: @mode)

            @mode
          end

          private

          def resolve_state_writer(context)
            if context.respond_to?(:state_writer) && context.state_writer
              context.state_writer
            elsif context.respond_to?(:reader_state_writer) && context.reader_state_writer
              context.reader_state_writer
            end
          rescue StandardError
            nil
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
end
