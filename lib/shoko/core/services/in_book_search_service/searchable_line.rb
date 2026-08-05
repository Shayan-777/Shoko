# frozen_string_literal: true

require 'shoko/core/models/value_normalizer'

module Shoko
  module Core
    module Services
      class InBookSearchService
        # One searchable plain line of a chapter, addressed by chapter and
        # parsed-line index.
        SearchableLine = Data.define(:chapter_index, :chapter_title, :line_index, :text) do
          def initialize(chapter_index:, chapter_title:, line_index:, text:)
            normalizer = Shoko::Core::Models::ValueNormalizer
            super(
              chapter_index: Integer(chapter_index), line_index: Integer(line_index),
              chapter_title: normalizer.immutable(chapter_title.to_s), text: normalizer.immutable(text.to_s)
            )
          end
        end
      end
    end
  end
end
