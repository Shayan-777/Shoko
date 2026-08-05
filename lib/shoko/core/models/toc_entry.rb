# frozen_string_literal: true

require_relative 'value_normalizer'

module Shoko
  module Core
    module Models
      # Represents a Table-of-Contents entry.
      TOCEntry = Data.define(:title, :href, :level, :chapter_index, :navigable) do
        def initialize(title:, href:, level:, chapter_index: nil, navigable: true)
          super(
            title: ValueNormalizer.immutable(title.to_s),
            href: href && ValueNormalizer.immutable(href.to_s),
            level: Integer(level),
            chapter_index: chapter_index.nil? ? nil : Integer(chapter_index),
            navigable: navigable == true
          )
        end
      end
    end
  end
end
