# frozen_string_literal: true

require_relative 'value_normalizer'

module Shoko
  module Core
    module Models
      # Normalized in-memory representation of a parsed ebook.
      # Format-specific metadata must live under +format_data+.
      BookData = Data.define(
        :title,
        :language,
        :authors,
        :chapters,
        :toc_entries,
        :resources,
        :metadata,
        :chapters_generation,
        :format_data
      ) do
        def initialize(title:, language:, authors:, chapters:, toc_entries:, resources:, metadata:,
                       chapters_generation: nil, format_data: {})
          super(
            title: ValueNormalizer.immutable(title.to_s),
            language: ValueNormalizer.immutable(language.to_s),
            authors: ValueNormalizer.immutable(Array(authors)),
            chapters: ValueNormalizer.immutable(Array(chapters)),
            toc_entries: ValueNormalizer.immutable(Array(toc_entries)),
            resources: ValueNormalizer.immutable(resources || {}),
            metadata: ValueNormalizer.immutable(metadata || {}),
            chapters_generation: chapters_generation && ValueNormalizer.immutable(chapters_generation.to_s),
            format_data: ValueNormalizer.immutable(format_data || {})
          )
        end
      end
    end
  end
end
