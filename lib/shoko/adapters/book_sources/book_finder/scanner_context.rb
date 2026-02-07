# frozen_string_literal: true

module Shoko
  module Adapters::BookSources
    class EPUBFinder
      # Context for directory scanning operations
      ScannerContext = Struct.new(:epubs, :visited_paths, :depth, keyword_init: true) do
        def can_scan?(dir, max_depth, max_files)
          depth <= max_depth &&
            epubs.length < max_files &&
            !visited_paths.include?(dir)
        end

        def mark_visited(dir)
          visited_paths.add(dir)
        end

        def with_deeper_depth
          self.class.new(
            epubs: epubs,
            visited_paths: visited_paths,
            depth: depth + 1
          )
        end
      end
    end
  end
end
