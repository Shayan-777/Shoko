# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Rendering
        module Models
          # Context object for rendering operations.
          # Replaces direct controller dependency in renderers with structured data access.
          class RenderingContext
            attr_reader :document, :page_calculator, :state, :config, :view_model

            def initialize(document:, state:, config:, view_model:, page_calculator: nil)
              @document = document
              @page_calculator = page_calculator
              @state = state
              @config = config
              @view_model = view_model
              freeze
            end

            # Convenience methods for common rendering needs
            def current_chapter
              @document&.get_chapter(@state.get(%i[reader current_chapter]))
            end

            def current_page_index
              @state.get(%i[reader current_page_index])
            end

            def view_mode
              Shoko::Application::Selectors::ConfigSelectors.view_mode(@state)
            end

            def page_numbering_mode
              Shoko::Application::Selectors::ConfigSelectors.page_numbering_mode(@state)
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
                @state.get(%i[reader total_pages])
              end
            end
          end
        end
      end
    end
  end
end
