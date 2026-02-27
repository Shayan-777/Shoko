# frozen_string_literal: true

require_relative 'base_action'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        module Actions
          # Action for updating the status message
          class UpdateMessageAction < BaseAction
            def initialize(message)
              super(message: message)
            end

            def apply(state)
              msg = payload[:message]
              safe = msg&.to_s
              state.update({ %i[reader message] => safe })
            end
          end
        end
      end
    end
  end
end
