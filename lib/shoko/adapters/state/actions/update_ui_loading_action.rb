# frozen_string_literal: true

require_relative 'update_state_action'

module Shoko
  module Adapters::State::Actions
    # Action for updating UI loading indicators.
    # Accepts any of: :loading_active, :loading_message, :loading_progress
    class UpdateUILoadingAction < UpdateUIAction
      ALLOWED = %i[loading_active loading_message loading_progress].freeze

      def initialize(**updates)
        super(allowed: ALLOWED, **updates)
      end
    end
  end
end
