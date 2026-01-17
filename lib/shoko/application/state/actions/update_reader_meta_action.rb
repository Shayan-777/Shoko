# frozen_string_literal: true

require_relative 'update_state_action'

module Shoko
  module Application
    module Actions
      # Action to update reader meta fields that are not pagination specific.
      # Allowed fields: :book_path, :running
      class UpdateReaderMetaAction < UpdateReaderAction
        ALLOWED = %i[book_path running].freeze

        def initialize(**updates)
          super(allowed: ALLOWED, **updates)
        end
      end
    end
  end
end
