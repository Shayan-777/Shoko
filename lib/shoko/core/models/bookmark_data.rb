# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Data object for adding bookmarks
      BookmarkData = Struct.new(:path, :chapter, :line_offset, :text)
    end
  end
end
