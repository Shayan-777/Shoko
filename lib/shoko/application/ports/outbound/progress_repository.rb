# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port interface for persisted reading progress.
        module ProgressRepository
          # @param book_path [String]
          # @param chapter_index [Integer]
          # @param line_offset [Integer]
          # @param anchor [Hash, nil] serialized DocumentAnchor for the position
          # @return [Core::Models::ReadingProgress]
          def save_for_book(book_path, chapter_index:, line_offset:, anchor: nil)
            raise NotImplementedError, "#{self.class} must implement #save_for_book"
          end

          # @param book_path [String]
          # @return [Core::Models::ReadingProgress, nil]
          def find_by_book_path(book_path)
            raise NotImplementedError, "#{self.class} must implement #find_by_book_path"
          end

          # @return [Hash<String, Core::Models::ReadingProgress>]
          def find_all
            raise NotImplementedError, "#{self.class} must implement #find_all"
          end

          # @param book_path [String]
          # @return [Boolean]
          def exists_for_book?(book_path)
            raise NotImplementedError, "#{self.class} must implement #exists_for_book?"
          end

          # @param book_path [String]
          # @return [Time, nil]
          def last_updated_at(book_path)
            raise NotImplementedError, "#{self.class} must implement #last_updated_at"
          end

          # @param limit [Integer, nil]
          # @return [Array<String>]
          def recent_books(limit: nil)
            raise NotImplementedError, "#{self.class} must implement #recent_books"
          end

          # @param book_path [String]
          # @param chapter_index [Integer]
          # @param line_offset [Integer]
          # @param anchor [Hash, nil] serialized DocumentAnchor for the position
          # @return [Core::Models::ReadingProgress]
          def save_if_further(book_path, chapter_index:, line_offset:, anchor: nil)
            raise NotImplementedError, "#{self.class} must implement #save_if_further"
          end
        end
      end
    end
  end
end
