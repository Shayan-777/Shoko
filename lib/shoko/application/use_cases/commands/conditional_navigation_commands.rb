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
          reader_state_reader = resolve_reader_state_reader(context)
          sidebar_visible = reader_state_reader&.sidebar_visible?

          routed_action = @primary_action
          if sidebar_visible && !sidebar_toggle_blocked?(reader_state_reader)
            # Route to sidebar command
            sidebar_command = SidebarCommand.new(@sidebar_action)
            sidebar_command.execute(context, params)
            routed_action = @sidebar_action
          else
            # Route to navigation command
            nav_command = NavigationCommand.new(@primary_action)
            nav_command.execute(context, params)
          end

          routed_action
        end

        def sidebar_toggle_blocked?(reader_state_reader)
          return false unless @sidebar_action == :toggle_toc

          reader_state_reader&.sidebar_active_tab != :toc
        rescue StandardError
          false
        end

        def resolve_reader_state_reader(context)
          return context.reader_state_reader if context.respond_to?(:reader_state_reader)

          nil
        rescue StandardError
          nil
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

          def space_or_sidebar
            new(:next_page, :toggle_toc) # Space: next page normally, toggle TOC when sidebar visible
          end
        end
      end
    end
  end
end
