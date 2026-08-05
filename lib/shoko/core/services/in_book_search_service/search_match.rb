# frozen_string_literal: true

require 'shoko/core/models/value_normalizer'

module Shoko
  module Core
    module Services
      class InBookSearchService
        # Single search hit with chapter location and context around the match.
        # +line_index+ is the chapter's PLAIN parsed-line index (paragraph
        # position); the result navigator re-locates the hit in the current
        # wrapped layout by its before/match/after context.
        SearchMatch = Data.define(
          :chapter_index,
          :chapter_title,
          :line_index,
          :before,
          :match,
          :after
        ) do
          def initialize(chapter_index:, chapter_title:, line_index:, before:, match:, after:)
            normalizer = Shoko::Core::Models::ValueNormalizer
            super(
              chapter_index: Integer(chapter_index), chapter_title: normalizer.immutable(chapter_title.to_s),
              line_index: Integer(line_index), before: normalizer.immutable(before.to_s),
              match: normalizer.immutable(match.to_s), after: normalizer.immutable(after.to_s)
            )
          end
        end
      end
    end
  end
end
