# frozen_string_literal: true

require_relative 'value_normalizer'

module Shoko
  module Core
    module Models
      # Data object for adding bookmarks. +anchor+ is an optional
      # DocumentAnchor-compatible value for the bookmarked line.
      BookmarkData = Data.define(:path, :chapter, :line_offset, :text, :anchor) do
        def initialize(path:, chapter:, line_offset:, text:, anchor: nil)
          super(
            path: ValueNormalizer.immutable(path.to_s),
            chapter: Integer(chapter),
            line_offset: Integer(line_offset),
            text: ValueNormalizer.immutable(text.to_s),
            anchor: ValueNormalizer.immutable(anchor)
          )
        end
      end
    end
  end
end
