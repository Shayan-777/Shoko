# frozen_string_literal: true

require_relative 'update_state_action'

module Shoko
  module Adapters::State::Actions
    # Action for updating various selection states.
    # @deprecated Use UpdateReaderAction.new(field: value) instead
    class UpdateSelectionsAction < UpdateReaderAction
    end
  end
end
