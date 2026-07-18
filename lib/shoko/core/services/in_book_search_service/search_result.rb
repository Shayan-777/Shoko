# frozen_string_literal: true

module Shoko
  module Core
    module Services
      class InBookSearchService
        # Search output payload.
        SearchResult = Struct.new(:query, :matches, :total_matches)
      end
    end
  end
end
