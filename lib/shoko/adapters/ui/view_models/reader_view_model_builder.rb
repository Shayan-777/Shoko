# frozen_string_literal: true

require_relative 'reader_view_model'
require_relative '../../../core/models/reader_settings'

module Shoko
  module Adapters
    module Ui
      module ViewModels
        # Builds ReaderViewModel from state reader ports and document, keeping controller lean.
        class ReaderViewModelBuilder
          def initialize(reader_state_reader:, config_reader:, doc:)
            @reader_state_reader = reader_state_reader
            @config_reader = config_reader
            @doc = doc
          end

          def build(page_info)
            ReaderViewModel.new(**attributes(page_info))
          end

          private

          def attributes(page_info)
            base_attributes.merge(page_info: page_info)
          end

          def base_attributes
            reader_attributes.merge(document_attributes).merge(config_attributes)
          end

          def total_chapter_count
            Array(@doc&.chapters).length
          end

          def chapter_title(index)
            chapter = @doc&.get_chapter(index)
            chapter&.title || ''
          end

          def doc_toc_entries
            Array(@doc&.toc_entries)
          end

          def reader_attributes
            {
              current_chapter: @reader_state_reader.current_chapter,
              total_chapters: total_chapter_count,
              current_page: @reader_state_reader.current_page,
              total_pages: @reader_state_reader.total_pages,
              chapter_title: chapter_title(@reader_state_reader.current_chapter),
              sidebar_visible: @reader_state_reader.sidebar_visible?,
              mode: @reader_state_reader.mode,
              message: @reader_state_reader.message,
              bookmarks: @reader_state_reader.bookmarks || [],
            }
          end

          def document_attributes
            {
              document_title: @doc&.title || '',
              toc_entries: doc_toc_entries,
              language: @doc&.language || 'en',
            }
          end

          def config_attributes
            {
              view_mode: @config_reader.view_mode || :single,
              show_page_numbers: @config_reader.show_page_numbers.nil? || @config_reader.show_page_numbers,
              page_numbering_mode: @config_reader.page_numbering_mode || :dynamic,
              line_spacing: @config_reader.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING,
            }
          end
        end
      end
    end
  end
end
