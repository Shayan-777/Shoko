# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Focused reader for navigation and pagination fields.
      module ReaderNavigationReader
        def current_chapter
          raise NotImplementedError, "#{self.class} must implement #current_chapter"
        end

        def total_chapters
          raise NotImplementedError, "#{self.class} must implement #total_chapters"
        end

        def current_page_index
          raise NotImplementedError, "#{self.class} must implement #current_page_index"
        end

        def left_page
          raise NotImplementedError, "#{self.class} must implement #left_page"
        end

        def right_page
          raise NotImplementedError, "#{self.class} must implement #right_page"
        end

        def single_page
          raise NotImplementedError, "#{self.class} must implement #single_page"
        end

        def current_page
          raise NotImplementedError, "#{self.class} must implement #current_page"
        end

        def page_map
          raise NotImplementedError, "#{self.class} must implement #page_map"
        end

        def total_pages
          raise NotImplementedError, "#{self.class} must implement #total_pages"
        end

        def pending_progress
          raise NotImplementedError, "#{self.class} must implement #pending_progress"
        end

        def book_path
          raise NotImplementedError, "#{self.class} must implement #book_path"
        end
      end
    end
  end
end
