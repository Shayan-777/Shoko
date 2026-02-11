# frozen_string_literal: true

module Shoko
  module Adapters::Output::Ui::Components
    module Sidebar
      # Renders list of TOC entries.
      class EntriesListRenderer
        def initialize(context)
          @context = context
        end

        def render
          @context.entries_layout.visible_items.each { |item| render_entry_item(item) }
        end

        private

        def render_entry_item(item)
          EntryRenderer.new(@context, item).render
        end
      end
    end
  end
end
