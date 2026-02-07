# frozen_string_literal: true

require_relative 'update_state_action'

module Shoko
  module Adapters::State::Actions
    # Action for updating page positions (current_page_index, left_page, right_page, single_page).
    # @deprecated Use UpdateReaderAction.new(current_page_index: n, left_page: m) instead
    class UpdatePageAction < UpdateReaderAction
    end
  end
end
