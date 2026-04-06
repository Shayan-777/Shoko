# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Normalized in-memory representation of a parsed ebook.
      # Format-specific metadata must live under +format_data+.
      BookData = Struct.new(
        :title,
        :language,
        :authors,
        :chapters,
        :toc_entries,
        :resources,
        :metadata,
        :chapters_generation,
        :format_data
      )
    end
  end
end
