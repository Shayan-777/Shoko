# frozen_string_literal: true

require_relative 'update_state_action'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        module Actions
          # Action for updating menu-related state under [:menu, *].
          # Uses the generic UpdateStateAction with :menu namespace.
          class UpdateMenuAction < UpdateStateAction
            def initialize(**updates)
              super(:menu, updates)
            end
          end
        end
      end
    end
  end
end
