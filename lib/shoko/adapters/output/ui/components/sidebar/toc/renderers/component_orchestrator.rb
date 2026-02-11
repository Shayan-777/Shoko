# frozen_string_literal: true

module Shoko
  module Adapters::Output::Ui::Components
    module Sidebar
      # Orchestrates rendering of all components.
      class ComponentOrchestrator
        def initialize(context)
          @context = context
        end

        def render
          return EmptyStateRenderer.new(@context).render if @context.entries.empty?

          HeaderRenderer.new(@context).render
          FilterInputRenderer.new(@context).render if @context.filter_active?
          EntriesListRenderer.new(@context).render
          ScrollbarRenderer.new(@context).render
        end
      end
    end
  end
end
