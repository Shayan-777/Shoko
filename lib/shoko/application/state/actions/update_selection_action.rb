# frozen_string_literal: true

require_relative 'update_state_action'

module Shoko
  module Application
    module Actions
      # Action for updating text selection state.
      # @deprecated Use UpdateReaderAction.new(selection: sel) instead
      class UpdateSelectionAction < UpdateReaderAction
        def initialize(selection)
          super(selection: selection)
        end
      end

      # Convenience action for clearing selection
      class ClearSelectionAction < UpdateSelectionAction
        def initialize
          super(nil)
        end
      end
    end
  end
end
