# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module ViewModels
        # Pure data structure for reader view rendering.
        # Eliminates component coupling to controllers and services.
        class ReaderViewModel
          attr_reader :current_chapter,
                      :total_chapters,
                      :current_page,
                      :total_pages,
                      :chapter_title,
                      :document_title,
                      :view_mode,
                      :mode,
                      :message,
                      :bookmarks,
                      :toc_entries,
                      :content_lines,
                      :page_info,
                      :show_page_numbers,
                      :page_numbering_mode,
                      :line_spacing,
                      :language,
                      :source_format

          def initialize(
            current_chapter: 0,
            total_chapters: 0,
            current_page: 0,
            total_pages: 0,
            chapter_title: '',
            document_title: '',
            view_mode: :single,
            mode: :read,
            message: nil,
            bookmarks: [],
            toc_entries: [],
            content_lines: [],
            page_info: {},
            show_page_numbers: true,
            page_numbering_mode: :dynamic,
            line_spacing: :normal,
            language: 'en',
            source_format: nil
          )
            @current_chapter = current_chapter
            @total_chapters = total_chapters
            @current_page = current_page
            @total_pages = total_pages
            @chapter_title = chapter_title
            @document_title = document_title
            @view_mode = view_mode
            @mode = mode
            @message = message
            @bookmarks = bookmarks
            @toc_entries = toc_entries
            @content_lines = content_lines
            @page_info = page_info
            @show_page_numbers = show_page_numbers
            @page_numbering_mode = page_numbering_mode
            @line_spacing = line_spacing
            @language = language
            @source_format = source_format
            freeze
          end

          # Derived properties
          def progress_percentage
            return 0 if total_pages.zero?

            ((current_page.to_f / total_pages) * 100).round(1)
          end

          def chapter_progress
            return '0/0' if total_chapters.zero?

            "#{current_chapter + 1}/#{total_chapters}"
          end

          def page_progress
            return '0/0' if total_pages.zero?

            "#{current_page + 1}/#{total_pages}"
          end

          def split_mode?
            view_mode == :split
          end

          def single_mode?
            view_mode == :single
          end

          def message?
            !message.nil? && !message.empty?
          end

          def bookmarks?
            !bookmarks.empty?
          end

          def toc?
            !toc_entries.empty?
          end

          # Create new instance with updates
          def with(**changes)
            self.class.new(**attributes_for_clone, **changes)
          end

          def attributes_for_clone
            progress_attributes
              .merge(display_attributes)
              .merge(content_attributes)
          end

          def progress_attributes
            {
              current_chapter: current_chapter,
              total_chapters: total_chapters,
              current_page: current_page,
              total_pages: total_pages,
              chapter_title: chapter_title,
            }
          end

          def display_attributes
            {
              document_title: document_title,
              view_mode: view_mode,
              mode: mode,
              message: message,
              show_page_numbers: show_page_numbers,
              page_numbering_mode: page_numbering_mode,
              line_spacing: line_spacing,
              language: language,
              source_format: source_format,
            }
          end

          def content_attributes
            {
              bookmarks: bookmarks,
              toc_entries: toc_entries,
              content_lines: content_lines,
              page_info: page_info,
            }
          end
        end
      end
    end
  end
end
