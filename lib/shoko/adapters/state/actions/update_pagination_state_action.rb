# frozen_string_literal: true

require_relative 'update_state_action'

module Shoko
  module Adapters::State::Actions
    # Action to update pagination-related reader state in a single, consistent way.
    # Allowed fields: :page_map, :total_pages, :last_width, :last_height, :total_chapters
    class UpdatePaginationStateAction < UpdateReaderAction
      ALLOWED = %i[page_map total_pages last_width last_height total_chapters].freeze

      def initialize(**updates)
        super(allowed: ALLOWED, **updates)
      end
    end
  end
end
