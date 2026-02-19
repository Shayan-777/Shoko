# frozen_string_literal: true

require_relative 'base_command'

module Shoko
  module Application
    module UseCases
      module Commands
        # Commands for sidebar navigation and interaction
        class SidebarCommand < BaseCommand
          def initialize(action, name: nil, description: nil)
            @action = action
            super(
              name: name || "sidebar_#{action}",
              description: description || "Sidebar #{action.to_s.tr('_', ' ')}"
            )
          end

          protected

          def perform(context, _params = {})
            ui_controller = context.ui_controller

            case @action
            when :up
              ui_controller.sidebar_up
            when :down
              ui_controller.sidebar_down
            when :select
              ui_controller.sidebar_select
            when :toggle_toc
              ui_controller.sidebar_toggle_toc
            else
              raise ExecutionError.new("Unknown sidebar action: #{@action}", command_name: name)
            end

            @action
          end

          class << self
            # Factory methods for common sidebar commands
            def up
              new(:up)
            end

            def down
              new(:down)
            end

            def select
              new(:select)
            end
          end
        end
      end
    end
  end
end
