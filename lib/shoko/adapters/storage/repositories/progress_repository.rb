# frozen_string_literal: true

require 'time'

require_relative 'base_repository'
require_relative 'storage/progress_file_store'

module Shoko
  module Adapters::Storage::Repositories
    # Repository for reading progress persistence, abstracting the underlying storage mechanism.
    #
    # This repository provides a clean domain interface for progress operations,
    # hiding the file-based persistence details from domain services.
    #
    # @example Saving progress
    #   repo = ProgressRepository.new(dependencies)
    #   repo.save_for_book('/path/to/book.epub', chapter_index: 3, line_offset: 150)
    #
    # @example Loading progress
    #   progress = repo.find_by_book_path('/path/to/book.epub')
    class ProgressRepository < BaseRepository
      # Progress data structure
      ProgressData = Struct.new(:chapter_index, :line_offset, :timestamp, keyword_init: true) do
        def to_h
          {
            chapter: chapter_index,
            line_offset: line_offset,
            timestamp: timestamp,
          }
        end

        def self.from_h(hash)
          return nil unless hash

          new(
            chapter_index: hash['chapter'] || hash[:chapter],
            line_offset: hash['line_offset'] || hash[:line_offset],
            timestamp: hash['timestamp'] || hash[:timestamp]
          )
        end
      end

      def initialize(file_writer:, logger: nil)
        super(logger: logger)
        @storage = Storage::ProgressFileStore.new(file_writer: file_writer)
      end

      # Save reading progress for a specific book
      #
      # @param book_path [String] Path to the EPUB file
      # @param chapter_index [Integer] Chapter index (0-based)
      # @param line_offset [Integer] Line offset within the chapter
      # @return [ProgressData] The saved progress data
      def save_for_book(book_path, chapter_index:, line_offset:)
        validate_required_params(
          { book_path: book_path, chapter_index: chapter_index, line_offset: line_offset },
          %i[book_path chapter_index line_offset]
        )

        begin
          @storage.save(book_path, chapter_index, line_offset)

          # Return the progress data that was saved
          ProgressData.new(
            chapter_index: chapter_index,
            line_offset: line_offset,
            timestamp: Time.now.iso8601
          )
        rescue StandardError => e
          handle_storage_error(e, "saving progress for #{book_path}")
        end
      end

      # Find reading progress for a specific book
      #
      # @param book_path [String] Path to the EPUB file
      # @return [ProgressData, nil] Progress data for the book, or nil if none exists
      def find_by_book_path(book_path)
        validate_required_params({ book_path: book_path }, [:book_path])

        begin
          progress_hash = @storage.load(book_path)
          ProgressData.from_h(progress_hash)
        rescue StandardError => e
          handle_storage_error(e, "loading progress for #{book_path}")
        end
      end

      # Find all reading progress across all books
      #
      # @return [Hash<String, ProgressData>] Hash mapping book paths to progress data
      def find_all
        all_progress = @storage.load_all
        all_progress.transform_values { |progress_hash| ProgressData.from_h(progress_hash) }
      rescue StandardError => e
        handle_storage_error(e, 'loading all progress data')
      end

      # Check if progress exists for a book
      #
      # @param book_path [String] Path to the EPUB file
      # @return [Boolean] True if progress data exists for the book
      def exists_for_book?(book_path)
        !find_by_book_path(book_path).nil?
      rescue StandardError => e
        handle_storage_error(e, "checking progress existence for #{book_path}")
      end

      # Get the timestamp of the last progress update for a book
      #
      # @param book_path [String] Path to the EPUB file
      # @return [Time, nil] Last update timestamp, or nil if no progress exists
      def last_updated_at(book_path)
        progress = find_by_book_path(book_path)
        ts = progress&.timestamp
        return nil unless ts

        Time.parse(ts)
      rescue StandardError => e
        handle_storage_error(e, "getting last update time for #{book_path}")
      end

      # Get books ordered by most recently read
      #
      # @param limit [Integer, nil] Maximum number of books to return
      # @return [Array<String>] Array of book paths ordered by recency
      def recent_books(limit: nil)
        all_progress = find_all
        sorted_paths = all_progress.sort_by do |_path, progress|
          ts = progress.timestamp
          ts ? Time.parse(ts) : Time.at(0)
        end.reverse.map(&:first)

        limit ? sorted_paths.take(limit) : sorted_paths
      rescue StandardError => e
        handle_storage_error(e, 'getting recent books')
      end

      # Update progress only if the new position is further than current
      #
      # @param book_path [String] Path to the EPUB file
      # @param chapter_index [Integer] Chapter index (0-based)
      # @param line_offset [Integer] Line offset within the chapter
      # @return [ProgressData] The saved progress data
      def save_if_further(book_path, chapter_index:, line_offset:)
        current_progress = find_by_book_path(book_path)

        should_save = if current_progress.nil?
                        true
                      else
                        cur_ch = current_progress.chapter_index
                        cur_off = current_progress.line_offset
                        chapter_index > cur_ch ||
                          (chapter_index == cur_ch && line_offset > cur_off)
                      end

        return save_for_book(book_path, chapter_index: chapter_index, line_offset: line_offset) if should_save

        current_progress
      rescue StandardError => e
        handle_storage_error(e, "conditionally saving progress for #{book_path}")
      end
    end
  end
end
