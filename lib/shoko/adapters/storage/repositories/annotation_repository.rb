# frozen_string_literal: true

require 'set'

require_relative 'base_repository'
require_relative '../../../core/ports/outbound/annotation_repository'
require_relative '../../../shared/hash_normalizer'
require_relative 'storage/annotation_file_store'

module Shoko
  module Adapters
    module Storage
      module Repositories
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
          include Core::Ports::Outbound::AnnotationRepository

          def initialize(file_writer:, logger: nil, storage: nil)
            super(logger: logger)
            @storage = storage || Storage::AnnotationFileStore.new(file_writer: file_writer)
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

            existing_ids = Set.new(find_by_book_path(book_path).filter_map { |annotation| annotation[:id] })
            persisted = @storage.add(book_path, text, note, range, chapter_index, page_meta)
            raise PersistenceError, "adding annotation for #{book_path} failed" unless persisted

            annotations = find_by_book_path(book_path)
            created = detect_created_annotation(existing_ids, annotations)
            ensure_entity_exists(created, 'Annotation')
            created
          end

          # Find all annotations for a specific book
          #
          # @param book_path [String] Path to the EPUB file
          # @return [Array<Hash>] Array of annotation hashes for the book
          def find_by_book_path(book_path)
            validate_required_params({ book_path: book_path }, [:book_path])
            Array(@storage.get(book_path)).map { |annotation| normalize_annotation(annotation) }
          end

          # Find all annotations across all books
          #
          # @return [Hash] Hash mapping book paths to annotation arrays
          def find_all
            normalize_annotation_map(@storage.all)
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
            @storage.update(book_path, annotation_id, note) == true
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
            @storage.delete(book_path, annotation_id) == true
          end

          # Find a specific annotation by ID
          #
          # @param book_path [String] Path to the EPUB file
          # @param annotation_id [String] ID of the annotation to find
          # @return [Hash, nil] The annotation hash, or nil if not found
          def find_by_id(book_path, annotation_id)
            annotations = find_by_book_path(book_path)
            annotations.find { |annotation| annotation[:id] == annotation_id }
          end

          # Get annotation count for a book
          #
          # @param book_path [String] Path to the EPUB file
          # @return [Integer] Number of annotations for the book
          def count_for_book(book_path)
            find_by_book_path(book_path).length
          end

          # Find annotations by chapter
          #
          # @param book_path [String] Path to the EPUB file
          # @param chapter_index [Integer] Chapter index to filter by
          # @return [Array<Hash>] Annotations in the specified chapter
          def find_by_chapter(book_path, chapter_index)
            annotations = find_by_book_path(book_path)
            annotations.select { |annotation| annotation[:chapter_index] == chapter_index }
          end

          # Check if any annotations exist at a text range
          #
          # @param book_path [String] Path to the EPUB file
          # @param chapter_index [Integer] Chapter index
          # @param range [Hash] Text range with :start and :end
          # @return [Boolean] True if annotations exist in this range
          def exists_in_range?(book_path, chapter_index, range)
            annotations = find_by_chapter(book_path, chapter_index)
            normalized_range = Shoko::Shared::HashNormalizer.symbolize_keys(range) || {}
            annotations.any? do |annotation|
              annotation_range = annotation[:range]
              next false unless annotation_range

              # Check for overlap
              annotation_start = annotation_range[:start]
              annotation_end = annotation_range[:end]
              range_start = normalized_range[:start]
              range_end = normalized_range[:end]

              annotation_start < range_end && range_start < annotation_end
            end
          end

          private

          def detect_created_annotation(existing_ids, annotations)
            annotations.reverse_each do |annotation|
              id = annotation[:id]
              return annotation if id && !existing_ids.include?(id)
            end

            annotations.last
          end

          def normalize_annotation(annotation)
            Shoko::Shared::HashNormalizer.deep_symbolize(annotation) || {}
          end

          def normalize_annotation_map(payload)
            return {} unless payload.is_a?(Hash)

            payload.each_with_object({}) do |(path, annotations), acc|
              acc[path.to_s] = Array(annotations).map { |annotation| normalize_annotation(annotation) }
            end
          end
        end
      end
    end
  end
end
