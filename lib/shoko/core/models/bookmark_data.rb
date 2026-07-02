# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Data object for adding bookmarks. +anchor+ is an optional serialized
      # DocumentAnchor hash for the bookmarked line.
      BookmarkData = Struct.new(:path, :chapter, :line_offset, :text, :anchor)
    end
  end
end
