# frozen_string_literal: true

require_relative 'base_command'
require_relative 'navigation_commands'
require_relative 'sidebar_commands'

module Shoko
  module Application
    module Commands
      # Commands that route to different actions based on application state
      class ConditionalNavigationCommand < BaseCommand
        def initialize(primary_action, sidebar_action, name: nil, description: nil)
          @primary_action = primary_action # Action when sidebar not visible
          @sidebar_action = sidebar_action # Action when sidebar is visible
          super(
            name: name || "conditional_#{primary_action}",
            description: description || "Conditional #{primary_action.to_s.tr('_', ' ')} navigation"
          )
        end

        protected

        def perform(context, params = {})
          state = context.state
          sidebar_visible = state.get(%i[reader sidebar_visible])

          if sidebar_visible
            # Route to sidebar command
            sidebar_command = SidebarCommand.new(@sidebar_action)
            sidebar_command.execute(context, params)
          else
            # Route to navigation command
            nav_command = NavigationCommand.new(@primary_action)
            nav_command.execute(context, params)
          end

          sidebar_visible ? @sidebar_action : @primary_action
        end

        class << self
          # Factory methods for common conditional navigation
          def up_or_sidebar
            new(:scroll_up, :up)
          end

          def down_or_sidebar
            new(:scroll_down, :down)
          end

          def select_or_sidebar
            new(:next_page, :select) # Enter key: next page normally, select in sidebar
          end
        end
      end
    end
  end
end
