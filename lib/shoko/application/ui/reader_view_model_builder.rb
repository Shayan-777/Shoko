# frozen_string_literal: true

module Shoko
  module Application
    module UI
      # Builds ReaderViewModel from state and document, keeping controller lean.
      class ReaderViewModelBuilder
        def initialize(state, doc)
          @state = state
          @doc = doc
        end

        def build(page_info)
          ViewModels::ReaderViewModel.new(**attributes(page_info))
        end

        private

        def attributes(page_info)
          base_attributes.merge(page_info: page_info)
        end

        def base_attributes
          {
            current_chapter: current_chapter_index,
            total_chapters: total_chapter_count,
            current_page: state_value(%i[reader current_page]),
            total_pages: state_value(%i[reader total_pages]),
            chapter_title: chapter_title(current_chapter_index),
            document_title: @doc&.title || '',
            view_mode: state_value(%i[config view_mode], :single),
            sidebar_visible: state_value(%i[reader sidebar_visible]),
            mode: state_value(%i[reader mode]),
            message: state_value(%i[reader message]),
            bookmarks: state_value(%i[reader bookmarks], []),
            toc_entries: doc_toc_entries,
            show_page_numbers: state_value(%i[config show_page_numbers], true),
            page_numbering_mode: state_value(%i[config page_numbering_mode], :dynamic),
            line_spacing: state_value(%i[config line_spacing], Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING),
            language: @doc&.language || 'en',
          }
        end

        def current_chapter_index
          state_value(%i[reader current_chapter])
        end

        def total_chapter_count
          Array(@doc&.chapters).length
        end

        def chapter_title(index)
          chapter = @doc&.get_chapter(index)
          chapter&.title || ''
        rescue StandardError
          ''
        end

        def doc_toc_entries
          return [] unless @doc.respond_to?(:toc_entries)

          Array(@doc.toc_entries)
        rescue StandardError
          []
        end

        def state_value(path, default = nil)
          value = @state.get(path)
          value.nil? ? default : value
        end
      end
    end
  end
end
