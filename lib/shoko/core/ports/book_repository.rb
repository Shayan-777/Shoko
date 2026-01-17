# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for reading progress persistence operations.
      # Adapters implementing this interface should handle reading position
      # storage and retrieval for EPUB books.
      #
      # Note: This port covers reading progress (not book metadata/library).
      # The name "BookRepository" is kept for compatibility but represents
      # progress tracking functionality.
      #
      # @example Implementing this port
      #   class FileProgressRepository
      #     include Shoko::Core::Ports::BookRepository
      #
      #     def save_progress(book_path, chapter_index:, line_offset:)
      #       # Implementation
      #     end
      #   end
      module BookRepository
        # Save reading progress for a specific book
        #
        # @param book_path [String] Path to the EPUB file
        # @param chapter_index [Integer] Chapter index (0-based)
        # @param line_offset [Integer] Line offset within the chapter
        # @return [Object] The saved progress data
        def save_progress(book_path, chapter_index:, line_offset:)
          raise NotImplementedError, "#{self.class} must implement #save_progress"
        end

        # Find reading progress for a specific book
        #
        # @param book_path [String] Path to the EPUB file
        # @return [Object, nil] Progress data for the book, or nil if none exists
        def find_progress(book_path)
          raise NotImplementedError, "#{self.class} must implement #find_progress"
        end

        # Find all reading progress across all books
        #
        # @return [Hash] Hash mapping book paths to progress data
        def find_all_progress
          raise NotImplementedError, "#{self.class} must implement #find_all_progress"
        end

        # Check if progress exists for a book
        #
        # @param book_path [String] Path to the EPUB file
        # @return [Boolean] True if progress data exists for the book
        def progress_exists?(book_path)
          raise NotImplementedError, "#{self.class} must implement #progress_exists?"
        end

        # Get books ordered by most recently read
        #
        # @param limit [Integer, nil] Maximum number of books to return
        # @return [Array<String>] Array of book paths ordered by recency
        def recent_books(limit: nil)
          raise NotImplementedError, "#{self.class} must implement #recent_books"
        end
      end
    end
  end
end
