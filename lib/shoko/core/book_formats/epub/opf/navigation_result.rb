# frozen_string_literal: true

module Shoko
  module Core::BookFormats::Epub
    # Value object for extracted TOC entries and title map.
    OPFNavigationResult = Struct.new(:toc_entries, :titles, keyword_init: true)
  end
end
