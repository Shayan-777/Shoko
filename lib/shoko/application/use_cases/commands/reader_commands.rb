# frozen_string_literal: true

require_relative 'base_command'

module Shoko
  module Application
    module UseCases
      module Commands
        # Handles reader mode transitions (help) via domain command flow.
        class ReaderModeCommand < BaseCommand
          def initialize(action)
            @action = action
            super(name: "reader_mode_#{action}", description: "Reader mode action #{action}")
          end

          protected

          def perform(context, _params = {})
            ui_controller = resolve_ui_controller(context)
            return :pass unless ui_controller

            case @action
            when :exit_help
              ui_controller.switch_mode(:read)
            else
              raise ExecutionError.new("Unknown reader mode action: #{@action}", command_name: name)
            end
          end

          private

          def resolve_ui_controller(context)
            context.respond_to?(:ui_controller) ? context.ui_controller : nil
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
