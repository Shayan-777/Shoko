# frozen_string_literal: true

require_relative 'base_repository'
require_relative 'storage/annotation_file_store'

module Shoko
  module Adapters::Storage::Repositories
    # Repository for annotation persistence, abstracting the underlying storage mechanism.
    #
    # This repository provides a clean domain interface for annotation operations,
    # hiding the file-based persistence details from domain services.
    #
    # @example Adding an annotation
    #   repo = AnnotationRepository.new(dependencies)
    #   annotation = repo.add_for_book(
    #     '/path/to/book.epub',
    #     text: 'Selected text',
    #     note: 'My note',
    #     range: { start: 100, end: 120 },
    #     chapter_index: 2
    #   )
    #
    # @example Getting annotations for a book
    #   annotations = repo.find_by_book_path('/path/to/book.epub')
    class AnnotationRepository < BaseRepository
      def initialize(file_writer:, logger: nil)
        super(logger: logger)
        @storage = Storage::AnnotationFileStore.new(file_writer: file_writer)
      end

      # Add a new annotation for a specific book
      #
      # @param book_path [String] Path to the EPUB file
      # @param text [String] The selected text being annotated
      # @param note [String] The annotation note
      # @param range [Hash] Text selection range with :start and :end
      # @param chapter_index [Integer] Chapter index (0-based)
      # @param page_meta [Hash, nil] Optional page metadata
      # @return [Hash] The created annotation data
      def add_for_book(book_path, text:, note:, range:, chapter_index:, page_meta: nil)
        validate_required_params(
          { book_path: book_path, text: text, note: note, range: range,
            chapter_index: chapter_index },
          %i[book_path text note range chapter_index]
        )

        begin
          @storage.add(book_path, text, note, range, chapter_index, page_meta)

          # Return the most recently created annotation
          annotations = find_by_book_path(book_path)
          annotations.max_by do |a|
            Time.parse(a['created_at'] || a['updated_at'] || Time.now.iso8601)
          end
        rescue StandardError => e
          handle_storage_error(e, "adding annotation for #{book_path}")
        end
      end

      # Find all annotations for a specific book
      #
      # @param book_path [String] Path to the EPUB file
      # @return [Array<Hash>] Array of annotation hashes for the book
      def find_by_book_path(book_path)
        validate_required_params({ book_path: book_path }, [:book_path])

        begin
          @storage.get(book_path) || []
        rescue StandardError => e
          handle_storage_error(e, "loading annotations for #{book_path}")
        end
      end

      # Find all annotations across all books
      #
      # @return [Hash] Hash mapping book paths to annotation arrays
      def find_all
        @storage.all || {}
      rescue StandardError => e
        handle_storage_error(e, 'loading all annotations')
      end

      # Update an existing annotation's note
      #
      # @param book_path [String] Path to the EPUB file
      # @param annotation_id [String] ID of the annotation to update
      # @param note [String] New note content
      # @return [Boolean] True if updated successfully
      def update_note(book_path, annotation_id, note)
        validate_required_params(
          { book_path: book_path, annotation_id: annotation_id, note: note },
          %i[book_path annotation_id note]
        )

        begin
          @storage.update(book_path, annotation_id, note)
          true
        rescue StandardError => e
          handle_storage_error(e, "updating annotation #{annotation_id} for #{book_path}")
        end
      end

      # Delete a specific annotation
      #
      # @param book_path [String] Path to the EPUB file
      # @param annotation_id [String] ID of the annotation to delete
      # @return [Boolean] True if deleted successfully
      def delete_by_id(book_path, annotation_id)
        validate_required_params(
          { book_path: book_path, annotation_id: annotation_id },
          %i[book_path annotation_id]
        )

        begin
          @storage.delete(book_path, annotation_id)
          true
        rescue StandardError => e
          handle_storage_error(e, "deleting annotation #{annotation_id} for #{book_path}")
        end
      end

      # Find a specific annotation by ID
      #
      # @param book_path [String] Path to the EPUB file
      # @param annotation_id [String] ID of the annotation to find
      # @return [Hash, nil] The annotation hash, or nil if not found
      def find_by_id(book_path, annotation_id)
        annotations = find_by_book_path(book_path)
        annotations.find { |a| a['id'] == annotation_id }
      rescue StandardError => e
        handle_storage_error(e, "finding annotation #{annotation_id} for #{book_path}")
      end

      # Get annotation count for a book
      #
      # @param book_path [String] Path to the EPUB file
      # @return [Integer] Number of annotations for the book
      def count_for_book(book_path)
        find_by_book_path(book_path).size
      rescue StandardError => e
        handle_storage_error(e, "counting annotations for #{book_path}")
      end

      # Find annotations by chapter
      #
      # @param book_path [String] Path to the EPUB file
      # @param chapter_index [Integer] Chapter index to filter by
      # @return [Array<Hash>] Annotations in the specified chapter
      def find_by_chapter(book_path, chapter_index)
        annotations = find_by_book_path(book_path)
        annotations.select { |a| a['chapter_index'] == chapter_index }
      rescue StandardError => e
        handle_storage_error(e, "finding annotations by chapter for #{book_path}")
      end

      # Check if any annotations exist at a text range
      #
      # @param book_path [String] Path to the EPUB file
      # @param chapter_index [Integer] Chapter index
      # @param range [Hash] Text range with :start and :end
      # @return [Boolean] True if annotations exist in this range
      def exists_in_range?(book_path, chapter_index, range)
        annotations = find_by_chapter(book_path, chapter_index)
        annotations.any? do |annotation|
          annotation_range = annotation['range']
          next false unless annotation_range

          # Check for overlap
          annotation_start = annotation_range['start'] || annotation_range[:start]
          annotation_end = annotation_range['end'] || annotation_range[:end]
          range_start = range['start'] || range[:start]
          range_end = range['end'] || range[:end]

          annotation_start < range_end && range_start < annotation_end
        end
      rescue StandardError => e
        handle_storage_error(e, "checking annotation range for #{book_path}")
      end
    end
  end
end
