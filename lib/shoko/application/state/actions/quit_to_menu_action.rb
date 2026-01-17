# frozen_string_literal: true

require_relative 'base_action'

module Shoko
  module Application
    module Actions
      # Stop the reader loop (used to return to menu)
      class QuitToMenuAction < BaseAction
        def apply(state)
          # Debug: Log when quit action is dispatched
          begin
            Shoko::Adapters::Monitoring::Logger.debug('quit_to_menu_action.apply',
                                                      caller_info: caller(1..3)&.join(' <- '))
          rescue StandardError
            # Ignore logging failures
          end
          state.update({ %i[reader running] => false })
        end
      end
    end
  end
end
