# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for annotation persistence operations.
      # Adapters implementing this interface should handle annotation storage
      # and retrieval for EPUB books.
      #
      # @example Implementing this port
      #   class FileAnnotationRepository
      #     include Shoko::Core::Ports::AnnotationRepository
      #
      #     def add_for_book(book_path, text:, note:, range:, chapter_index:, page_meta: nil)
      #       # Implementation
      #     end
      #   end
      module AnnotationRepository
        # Add a new annotation for a specific book
        #
        # @param book_path [String] Path to the EPUB file
        # @param text [String] The selected text being annotated
        # @param note [String] The annotation note
        # @param range [Hash] Text selection range with :start and :end
        # @param chapter_index [Integer] Chapter index (0-based)
        # @param page_meta [Hash, nil] Optional page metadata
        # @return [Object] The created annotation
        def add_for_book(book_path, text:, note:, range:, chapter_index:, page_meta: nil)
          raise NotImplementedError, "#{self.class} must implement #add_for_book"
        end

        # Find all annotations for a specific book
        #
        # @param book_path [String] Path to the EPUB file
        # @return [Array] Array of annotations for the book
        def find_by_book_path(book_path)
          raise NotImplementedError, "#{self.class} must implement #find_by_book_path"
        end

        # Find all annotations across all books
        #
        # @return [Hash] Hash mapping book paths to annotation arrays
        def find_all
          raise NotImplementedError, "#{self.class} must implement #find_all"
        end

        # Update an existing annotation's note
        #
        # @param book_path [String] Path to the EPUB file
        # @param annotation_id [String] ID of the annotation to update
        # @param note [String] New note content
        # @return [Boolean] True if updated successfully
        def update_note(book_path, annotation_id, note)
          raise NotImplementedError, "#{self.class} must implement #update_note"
        end

        # Delete a specific annotation
        #
        # @param book_path [String] Path to the EPUB file
        # @param annotation_id [String] ID of the annotation to delete
        # @return [Boolean] True if deleted successfully
        def delete_by_id(book_path, annotation_id)
          raise NotImplementedError, "#{self.class} must implement #delete_by_id"
        end

        # Find a specific annotation by ID
        #
        # @param book_path [String] Path to the EPUB file
        # @param annotation_id [String] ID of the annotation to find
        # @return [Object, nil] The annotation, or nil if not found
        def find_by_id(book_path, annotation_id)
          raise NotImplementedError, "#{self.class} must implement #find_by_id"
        end

        # Get annotation count for a book
        #
        # @param book_path [String] Path to the EPUB file
        # @return [Integer] Number of annotations for the book
        def count_for_book(book_path)
          raise NotImplementedError, "#{self.class} must implement #count_for_book"
        end

        # Find annotations by chapter
        #
        # @param book_path [String] Path to the EPUB file
        # @param chapter_index [Integer] Chapter index to filter by
        # @return [Array] Annotations in the specified chapter
        def find_by_chapter(book_path, chapter_index)
          raise NotImplementedError, "#{self.class} must implement #find_by_chapter"
        end
      end
    end
  end
end
