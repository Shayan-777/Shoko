# frozen_string_literal: true

require 'time'

require_relative 'base_repository'
require_relative 'storage/progress_file_store'
require 'shoko/application/ports/outbound/progress_repository'
require 'shoko/core/models/reading_progress'

module Shoko
  module Adapters
    module Storage
      module Repositories
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
          include Shoko::Application::Ports::Outbound::ProgressRepository

          def initialize(file_writer:, logger: nil)
            super(logger: logger)
            @storage = Storage::ProgressFileStore.new(file_writer: file_writer)
          end

          # Save reading progress for a specific book
          #
          # @param book_path [String] Path to the EPUB file
          # @param chapter_index [Integer] Chapter index (0-based)
          # @param line_offset [Integer] Line offset within the chapter
          # @param anchor [Hash, nil] Serialized DocumentAnchor for the position
          # @return [Core::Models::ReadingProgress] The saved progress data
          def save_for_book(book_path, chapter_index:, line_offset:, anchor: nil)
            validate_required_params(
              { book_path: book_path, chapter_index: chapter_index, line_offset: line_offset },
              %i[book_path chapter_index line_offset]
            )

            begin
              @storage.save(book_path, chapter_index, line_offset, anchor)

              # Return the progress data that was saved
              Shoko::Core::Models::ReadingProgress.new(
                chapter_index: chapter_index,
                line_offset: line_offset,
                timestamp: Time.now.iso8601,
                anchor: anchor
              )
            rescue Shoko::Error => e
              handle_storage_error(e, "saving progress for #{book_path}")
            end
          end

          # Find reading progress for a specific book
          #
          # @param book_path [String] Path to the EPUB file
          # @return [Core::Models::ReadingProgress, nil] Progress data for the book, or nil if none exists
          def find_by_book_path(book_path)
            validate_required_params({ book_path: book_path }, [:book_path])

            begin
              progress_hash = @storage.load(book_path)
              Shoko::Core::Models::ReadingProgress.from_h(progress_hash)
            rescue Shoko::Error => e
              handle_storage_error(e, "loading progress for #{book_path}")
            end
          end

          # Find all reading progress across all books
          #
          # @return [Hash<String, Core::Models::ReadingProgress>] Hash mapping book paths to progress data
          def find_all
            all_progress = @storage.load_all
            all_progress.transform_values { |progress_hash| Shoko::Core::Models::ReadingProgress.from_h(progress_hash) }
          rescue Shoko::Error => e
            handle_storage_error(e, 'loading all progress data')
          end

          # Check if progress exists for a book
          #
          # @param book_path [String] Path to the EPUB file
          # @return [Boolean] True if progress data exists for the book
          def exists_for_book?(book_path)
            !find_by_book_path(book_path).nil?
          rescue Shoko::Error => e
            handle_storage_error(e, "checking progress existence for #{book_path}")
          end

          # Get the timestamp of the last progress update for a book
          #
          # @param book_path [String] Path to the EPUB file
          # @return [Time, nil] Last update timestamp, or nil if no progress exists
          def last_updated_at(book_path)
            progress = find_by_book_path(book_path)
            parse_timestamp(progress&.timestamp)
          rescue Shoko::Error => e
            handle_storage_error(e, "getting last update time for #{book_path}")
          end

          # Get books ordered by most recently read
          #
          # @param limit [Integer, nil] Maximum number of books to return
          # @return [Array<String>] Array of book paths ordered by recency
          def recent_books(limit: nil)
            all_progress = find_all
            sorted_paths = all_progress.sort_by do |_path, progress|
              parse_timestamp(progress.timestamp) || Time.at(0)
            end.reverse.map(&:first)

            limit ? sorted_paths.take(limit) : sorted_paths
          rescue Shoko::Error => e
            handle_storage_error(e, 'getting recent books')
          end

          # Update progress only if the new position is further than current
          #
          # @param book_path [String] Path to the EPUB file
          # @param chapter_index [Integer] Chapter index (0-based)
          # @param line_offset [Integer] Line offset within the chapter
          # @param anchor [Hash, nil] Serialized DocumentAnchor for the position
          # @return [Core::Models::ReadingProgress] The saved progress data
          def save_if_further(book_path, chapter_index:, line_offset:, anchor: nil)
            current_progress = find_by_book_path(book_path)

            should_save = if current_progress.nil?
                            true
                          else
                            cur_ch = current_progress.chapter_index
                            cur_off = current_progress.line_offset
                            chapter_index > cur_ch ||
                              (chapter_index == cur_ch && line_offset > cur_off)
                          end

            if should_save
              return save_for_book(book_path, chapter_index: chapter_index, line_offset: line_offset, anchor: anchor)
            end

            current_progress
          rescue Shoko::Error => e
            handle_storage_error(e, "conditionally saving progress for #{book_path}")
          end

          private

          # Stored timestamps are written by us as ISO 8601, but the file lives
          # on disk and may be corrupt or hand-edited. Time.parse raises
          # ArgumentError on garbage (not a Shoko::Error), so an unparseable
          # timestamp degrades to "unknown" (nil) rather than crashing reads.
          def parse_timestamp(value)
            return nil if value.nil?

            Time.parse(value.to_s)
          rescue ArgumentError, TypeError
            nil
          end
        end
      end
    end
  end
end
