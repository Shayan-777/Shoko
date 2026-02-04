# frozen_string_literal: true

module Shoko
  module Adapters::Output::Ui::Components
    module Reading
      # Factory for creating appropriate view renderers based on configuration
      class ViewRendererFactory
        def self.create(_state, dependencies)
          config_reader = resolve_config_reader(dependencies)
          view_mode = config_reader&.view_mode || :single
          page_numbering_mode = config_reader&.page_numbering_mode || :dynamic

          case view_mode
          when :split
            SplitViewRenderer.new(dependencies)
          else
            SingleViewRenderer.new(dependencies, page_numbering_mode: page_numbering_mode)
          end
        end

        def self.resolve_config_reader(dependencies)
          dependencies.resolve(:config_reader)
        rescue StandardError
          nil
        end
      end
    end
  end
end
