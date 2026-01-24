# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Rendering
        module Models
          # Context object for rendering operations.
          # Replaces direct controller dependency in renderers with structured data access.
          class RenderingContext
            attr_reader :document, :page_calculator, :state, :config, :view_model,
                        :config_reader, :reader_state_reader

            def initialize(document:, state:, config:, view_model:, page_calculator: nil,
                           config_reader: nil, reader_state_reader: nil)
              @document = document
              @page_calculator = page_calculator
              @state = state
              @config = config
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
              @config_reader&.view_mode || :split
            end

            def page_numbering_mode
              @config_reader&.page_numbering_mode || :dynamic
            end

            # Dynamic mode page data access
            def get_page_data(index)
              return nil unless @page_calculator && page_numbering_mode == :dynamic

              @page_calculator.get_page(index)
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
