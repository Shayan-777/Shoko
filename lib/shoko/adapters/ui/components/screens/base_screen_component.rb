# frozen_string_literal: true

require_relative '../base_component'
require_relative '../render_style'
require 'shoko/shared/terminal/text_metrics'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Base component for all screen renderers
          class BaseScreenComponent < BaseComponent
            def initialize(services = nil)
              super
            end

            # Screens typically take the full available height
            def preferred_height(available_height)
              available_height
            end

            protected

            def write_header(surface, bounds, title, help_text = nil)
              w = bounds.width
              surface.write(bounds, 1, 2, title)
              return unless help_text

              help_width = Shoko::Shared::Terminal::TextMetrics.visible_length(help_text)
              surface.write(bounds, 1, [w - help_width - 2, w / 2].max, help_text)
            end

            def write_footer(surface, bounds, text)
              surface.write(bounds, bounds.height - 1, 2, text)
            end

            def write_empty_message(surface, bounds, message)
              col = [(bounds.width - Shoko::Shared::Terminal::TextMetrics.visible_length(message)) / 2, 1].max
              row = bounds.height / 2
              surface.write(bounds, row, col, message)
            end

            def write_selection_pointer(surface, bounds, row, selected: true)
              text = selected ? Shoko::Adapters::Ui::Components::RenderStyle.selection_pointer_colored : '  '
              surface.write(bounds, row, 2, text)
            end
          end
        end
      end
    end
  end
end
