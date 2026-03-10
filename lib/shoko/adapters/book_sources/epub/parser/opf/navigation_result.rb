# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Value object for extracted TOC entries and title map.
        OPFNavigationResult = Struct.new(:toc_entries, :titles)
      end
    end
  end
end
