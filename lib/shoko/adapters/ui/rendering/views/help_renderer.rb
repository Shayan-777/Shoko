# frozen_string_literal: true

require_relative 'base_view_renderer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Reading
          # Renderer for help screen display
          class HelpRenderer < BaseViewRenderer
            HELP_LINES = [
              '',
              'Navigation Keys:',
              '  j / ↓     Scroll down',
              '  k / ↑     Scroll up',
              '  l / →     Next page',
              '  h / ←     Previous page',
              '  SPACE     Next page',
              '  n         Next chapter',
              '  p         Previous chapter',
              '  g         Go to beginning of chapter',
              '  G         Go to end of chapter',
              '',
              'View Options:',
              '  v         Toggle split/single view',
              '  P         Toggle page numbering mode (Absolute/Dynamic)',
              '  + / -     Adjust line spacing',
              '',
              'Features:',
              '  t         Show Table of Contents',
              '  b         Add a bookmark',
              '  B         Show bookmarks',
              '  A         Show annotations sidebar',
              '  /         In-book search',
              '  d         Dictionary lookup',
              '  T         Translator',
              '  Ctrl+A    Toggle annotations overlay',
              '',
              'Other Keys:',
              '  ?         Show/hide this help',
              '  q         Quit to menu',
              '  Q         Quit application',
              '',
              '',
              'Press any key to return to reading...',
            ].freeze

            def render_with_context(surface, bounds, _context)
              b_height = bounds.height
              b_width  = bounds.width
              start_row = [(b_height - HELP_LINES.size) / 2, 1].max

              HELP_LINES.each_with_index do |line, idx|
                row = start_row + idx
                break if row >= b_height - 2

                text_width = Shoko::Shared::Terminal::TextMetrics.visible_length(line)
                col = [(b_width - text_width) / 2, 1].max
                surface.write(bounds,
                              row,
                              col,
                              Shoko::Adapters::Ui::Constants::Ui::COLOR_TEXT_PRIMARY + line + Shoko::Shared::Terminal::Ansi::RESET)
              end
            end
          end
        end
      end
    end
  end
end
