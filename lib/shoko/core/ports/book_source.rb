# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for loading and parsing book content.
      # Adapters implementing this interface should handle loading
      # book data from various sources (EPUB files, cache, etc.).
      #
      # @example Implementing this port
      #   class EpubBookSource
      #     include Shoko::Core::Ports::BookSource
      #
      #     def load_book(path)
      #       # Implementation
      #     end
      #   end
      module BookSource
        # Load book metadata and content from a source
        #
        # @param path [String] Path to the book file
        # @return [Object] Book data object with metadata and content
        def load_book(path)
          raise NotImplementedError, "#{self.class} must implement #load_book"
        end

        # Check if a file is a valid book format
        #
        # @param path [String] Path to check
        # @return [Boolean] True if the file is a valid book
        def valid_book?(path)
          raise NotImplementedError, "#{self.class} must implement #valid_book?"
        end

        # Get book metadata without loading full content
        #
        # @param path [String] Path to the book file
        # @return [Hash] Metadata hash with title, authors, etc.
        def metadata(path)
          raise NotImplementedError, "#{self.class} must implement #metadata"
        end

        # Get chapter content by index
        #
        # @param path [String] Path to the book file
        # @param chapter_index [Integer] Chapter index (0-based)
        # @return [Object] Chapter content
        def chapter(path, chapter_index)
          raise NotImplementedError, "#{self.class} must implement #chapter"
        end

        # Get table of contents
        #
        # @param path [String] Path to the book file
        # @return [Array] Array of TOC entries
        def table_of_contents(path)
          raise NotImplementedError, "#{self.class} must implement #table_of_contents"
        end

        # Get total chapter count
        #
        # @param path [String] Path to the book file
        # @return [Integer] Number of chapters
        def chapter_count(path)
          raise NotImplementedError, "#{self.class} must implement #chapter_count"
        end
      end
    end
  end
end
