# frozen_string_literal: true

require_relative 'update_state_action'

module Shoko
  module Application
    module Actions
      # Action for updating various selection states.
      # @deprecated Use UpdateReaderAction.new(field: value) instead
      class UpdateSelectionsAction < UpdateReaderAction
        def initialize(**updates)
          super(**updates)
        end
      end
    end
  end
end
