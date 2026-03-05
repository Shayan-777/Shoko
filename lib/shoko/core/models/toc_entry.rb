# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Represents a Table-of-Contents entry.
      TOCEntry = Struct.new(:title, :href, :level, :chapter_index, :navigable) do
        def initialize(title:, href:, level:, chapter_index: nil, navigable: true)
          super
        end
      end
    end
  end
end
