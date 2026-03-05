# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Normalized in-memory representation of a parsed ebook.
      # EPUB-specific fields (opf_path, spine, chapter_hrefs, container_path,
      # container_xml) are kept for backward compatibility.  New formats should
      # store format-specific data in +format_data+ instead.
      BookData = Struct.new(
        :title,
        :language,
        :authors,
        :chapters,
        :toc_entries,
        :opf_path,
        :spine,
        :chapter_hrefs,
        :resources,
        :metadata,
        :container_path,
        :container_xml,
        :chapters_generation,
        :format_data
      )
    end
  end
end
