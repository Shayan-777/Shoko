# frozen_string_literal: true

module Shoko
  module Adapters
    module Runtime
      module SessionState
        module Actions
          # Action for updating the status message, applied through
          # StateStore#dispatch.
          class UpdateMessageAction
            def initialize(message)
              @message = message
            end

            def apply(state)
              state.update({ %i[reader message] => @message&.to_s })
            end
          end
        end
      end
    end
  end
end
