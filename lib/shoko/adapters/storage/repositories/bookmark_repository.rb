# frozen_string_literal: true

require_relative 'base_repository'
require 'shoko/core/models/bookmark_data'
require 'shoko/application/ports/outbound/bookmark_repository'
require_relative 'storage/bookmark_file_store'

module Shoko
  module Adapters
    module Storage
      module Repositories
        # Repository for bookmark persistence, abstracting the underlying storage mechanism.
        #
        # This repository provides a clean domain interface for bookmark operations,
        # hiding the file-based persistence details from domain services.
        #
        # @example Adding a bookmark
        #   repo = BookmarkRepository.new(dependencies)
        #   repo.add_for_book('/path/to/book.epub', chapter: 2, line: 50, text: 'Important quote')
        #
        # @example Getting bookmarks for a book
        #   bookmarks = repo.find_by_book_path('/path/to/book.epub')
        class BookmarkRepository < BaseRepository
          include Application::Ports::Outbound::BookmarkRepository

          def initialize(file_writer:, logger: nil)
            super(logger: logger)
            @storage = Storage::BookmarkFileStore.new(file_writer: file_writer, logger: logger)
          end

          # Add a bookmark for a specific book
          #
          # @param book_path [String] Path to the EPUB file
          # @param chapter_index [Integer] Chapter index (0-based)
          # @param line_offset [Integer] Line offset within the chapter
          # @param text_snippet [String] Text snippet for the bookmark
          # @param anchor [Hash, nil] Serialized DocumentAnchor for the line
          # @return [Models::Bookmark] The created bookmark
          def add_for_book(book_path, chapter_index:, line_offset:, text_snippet:, anchor: nil)
            validate_required_params(
              { book_path: book_path, chapter_index: chapter_index, line_offset: line_offset },
              %i[book_path chapter_index line_offset]
            )

            begin
              @storage.add(build_bookmark_data(book_path, chapter_index: chapter_index,
                                                          line_offset: line_offset,
                                                          text_snippet: text_snippet, anchor: anchor))
              latest_bookmark_for(book_path)
            rescue Shoko::Error => e
              handle_storage_error(e, "adding bookmark for #{book_path}")
            end
          end

          # Find all bookmarks for a specific book
          #
          # @param book_path [String] Path to the EPUB file
          # @return [Array<Models::Bookmark>] Array of bookmarks for the book
          def find_by_book_path(book_path)
            validate_required_params({ book_path: book_path }, [:book_path])

            begin
              @storage.get(book_path) || []
            rescue Shoko::Error => e
              handle_storage_error(e, "loading bookmarks for #{book_path}")
            end
          end

          # Delete a specific bookmark
          #
          # @param book_path [String] Path to the EPUB file
          # @param bookmark [Models::Bookmark] The bookmark to delete
          # @return [Boolean] True if deleted successfully
          def delete_for_book(book_path, bookmark)
            # Ensure entity existence takes precedence for clearer error semantics
            ensure_entity_exists(bookmark, 'Bookmark')
            validate_required_params({ book_path: book_path }, %i[book_path])

            begin
              @storage.delete(book_path, bookmark)
              true
            rescue Shoko::Error => e
              handle_storage_error(e, "deleting bookmark for #{book_path}")
            end
          end

          # Check if a bookmark exists at the given position
          #
          # @param book_path [String] Path to the EPUB file
          # @param chapter_index [Integer] Chapter index
          # @param line_offset [Integer] Line offset within the chapter
          # @return [Boolean] True if a bookmark exists at this position
          def exists_at_position?(book_path, chapter_index, line_offset)
            bookmarks = find_by_book_path(book_path)
            bookmarks.any? do |bookmark|
              bookmark.chapter_index == chapter_index && bookmark.line_offset == line_offset
            end
          rescue Shoko::Error => e
            handle_storage_error(e, "checking bookmark existence for #{book_path}")
          end

          # Get bookmark count for a book
          #
          # @param book_path [String] Path to the EPUB file
          # @return [Integer] Number of bookmarks for the book
          def count_for_book(book_path)
            find_by_book_path(book_path).size
          rescue Shoko::Error => e
            handle_storage_error(e, "counting bookmarks for #{book_path}")
          end

          # Find bookmark at a specific position
          #
          # @param book_path [String] Path to the EPUB file
          # @param chapter_index [Integer] Chapter index
          # @param line_offset [Integer] Line offset within the chapter
          # @return [Models::Bookmark, nil] The bookmark at this position, or nil
          def find_at_position(book_path, chapter_index, line_offset)
            bookmarks = find_by_book_path(book_path)
            bookmarks.find do |bookmark|
              bookmark.chapter_index == chapter_index && bookmark.line_offset == line_offset
            end
          rescue Shoko::Error => e
            handle_storage_error(e, "finding bookmark at position for #{book_path}")
          end

          def build_bookmark_data(book_path, chapter_index:, line_offset:, text_snippet:, anchor: nil)
            Core::Models::BookmarkData.new(
              path: book_path,
              chapter: chapter_index,
              line_offset: line_offset,
              text: text_snippet || '',
              anchor: anchor
            )
          end

          def latest_bookmark_for(book_path)
            find_by_book_path(book_path).max_by(&:created_at)
          end
        end
      end
    end
  end
end
