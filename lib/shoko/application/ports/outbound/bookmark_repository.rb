# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port interface for bookmark persistence operations.
        # Adapters implementing this interface should handle bookmark storage
        # and retrieval for EPUB books.
        #
        # @example Implementing this port
        #   class FileBookmarkRepository
        #     include Shoko::Application::Ports::Outbound::BookmarkRepository
        #
        #     def add_for_book(book_path, chapter_index:, line_offset:, text_snippet:)
        #       # Implementation
        #     end
        #   end
        module BookmarkRepository
          # Add a bookmark for a specific book
          #
          # @param book_path [String] Path to the EPUB file
          # @param chapter_index [Integer] Chapter index (0-based)
          # @param line_offset [Integer] Line offset within the chapter
          # @param text_snippet [String] Text snippet for the bookmark
          # @return [Object] The created bookmark
          def add_for_book(book_path, chapter_index:, line_offset:, text_snippet:)
            raise NotImplementedError, "#{self.class} must implement #add_for_book"
          end

          # Find all bookmarks for a specific book
          #
          # @param book_path [String] Path to the EPUB file
          # @return [Array] Array of bookmarks for the book
          def find_by_book_path(book_path)
            raise NotImplementedError, "#{self.class} must implement #find_by_book_path"
          end

          # Delete a specific bookmark
          #
          # @param book_path [String] Path to the EPUB file
          # @param bookmark [Object] The bookmark to delete
          # @return [Boolean] True if deleted successfully
          def delete_for_book(book_path, bookmark)
            raise NotImplementedError, "#{self.class} must implement #delete_for_book"
          end

          # Check if a bookmark exists at the given position
          #
          # @param book_path [String] Path to the EPUB file
          # @param chapter_index [Integer] Chapter index
          # @param line_offset [Integer] Line offset within the chapter
          # @return [Boolean] True if a bookmark exists at this position
          def exists_at_position?(book_path, chapter_index, line_offset)
            raise NotImplementedError, "#{self.class} must implement #exists_at_position?"
          end

          # Find bookmark at a specific position
          #
          # @param book_path [String] Path to the EPUB file
          # @param chapter_index [Integer] Chapter index
          # @param line_offset [Integer] Line offset within the chapter
          # @return [Object, nil] The bookmark at this position, or nil
          def find_at_position(book_path, chapter_index, line_offset)
            raise NotImplementedError, "#{self.class} must implement #find_at_position"
          end

          # Get bookmark count for a book
          #
          # @param book_path [String] Path to the EPUB file
          # @return [Integer] Number of bookmarks for the book
          def count_for_book(book_path)
            raise NotImplementedError, "#{self.class} must implement #count_for_book"
          end
        end
      end
    end
  end
end
