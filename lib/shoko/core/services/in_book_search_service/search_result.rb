# frozen_string_literal: true

require 'shoko/core/models/value_normalizer'

module Shoko
  module Core
    module Services
      class InBookSearchService
        # Search output payload.
        SearchResult = Data.define(:query, :matches, :total_matches) do
          def initialize(query:, matches:, total_matches:)
            normalizer = Shoko::Core::Models::ValueNormalizer
            super(
              query: normalizer.immutable(query.to_s), matches: normalizer.immutable(Array(matches)),
              total_matches: Integer(total_matches)
            )
          end
        end
      end
    end
  end
end
