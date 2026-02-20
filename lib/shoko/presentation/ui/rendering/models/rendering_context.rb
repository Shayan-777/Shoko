# frozen_string_literal: true

module Shoko
  module Presentation
    module Ui
      module Rendering
        module Models
          # Context object for rendering operations.
          # Replaces direct controller dependency in renderers with structured data access.
          class RenderingContext
            attr_reader :document, :page_calculator, :view_model,
                        :config_reader, :reader_state_reader

            def initialize(document:, page_calculator: nil,
                           config_reader: nil, reader_state_reader: nil,
                           view_model: nil)
              @document = document
              @page_calculator = page_calculator
              @view_model = view_model
              @config_reader = config_reader
              @reader_state_reader = reader_state_reader
              freeze
            end

            # Convenience methods for common rendering needs
            def current_chapter
              chapter_index = @reader_state_reader&.current_chapter || 0
              @document&.get_chapter(chapter_index)
            end

            def current_page_index
              @reader_state_reader&.current_page_index || 0
            end

            def view_mode
              @config_reader&.view_mode || :single
            end

            def page_numbering_mode
              @config_reader&.page_numbering_mode || :dynamic
            end

            # Dynamic mode page data access
            def get_page_data(index, width: nil, height: nil, sidebar_visible: nil)
              return nil unless @page_calculator && page_numbering_mode == :dynamic

              @page_calculator.get_page(
                index,
                width: width,
                height: height,
                sidebar_visible: sidebar_visible
              )
            end

            def total_pages
              if @page_calculator && page_numbering_mode == :dynamic
                @page_calculator.total_pages
              else
                @reader_state_reader&.total_pages || 0
              end
            end
          end
        end
      end
    end
  end
end
