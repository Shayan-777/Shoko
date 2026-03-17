# frozen_string_literal: true

require_relative 'single_view_renderer'
require_relative 'split_view_renderer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Reading
          # Factory for creating appropriate view renderers based on configuration
          class ViewRendererFactory
            def self.create(render_dependencies)
              config_reader = render_dependencies&.config_reader
              view_mode = config_reader&.view_mode || :single
              page_numbering_mode = config_reader&.page_numbering_mode || :dynamic

              case view_mode
              when :split
                SplitViewRenderer.new(render_dependencies)
              else
                SingleViewRenderer.new(render_dependencies, page_numbering_mode: page_numbering_mode)
              end
            end
          end
        end
      end
    end
  end
end
