# frozen_string_literal: true

require_relative '../base_component'
require_relative '../ui/spinner'
require 'shoko/shared/terminal/text_metrics'
require 'shoko/shared/terminal/ansi'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Compact bottom-right toast shown in the menu while the library is being
          # pre-paginated in the background. Reads only the menu's prepagination
          # fields and animates via the shared monotonic-clock Spinner, so the
          # menu's existing poll loop keeps it spinning without extra timers.
          class PrepaginationToastComponent < BaseComponent
            include Adapters::Ui::Constants::Ui

            Ansi = Shoko::Shared::Terminal::Ansi
            Spinner = Adapters::Ui::Components::Ui::Spinner
            TextMetrics = Shoko::Shared::Terminal::TextMetrics
            LABEL = 'Pre-paginating library'

            def initialize(menu_state_reader:)
              super()
              @menu_state_reader = menu_state_reader
            end

            def do_render(surface, bounds)
              return unless active?
              return if bounds.width < 12 || bounds.height < 1

              label = toast_label
              col = [bounds.width - TextMetrics.visible_length(label), 1].max
              surface.write(bounds, bounds.height, col, label)
            end

            private

            attr_reader :menu_state_reader

            def active?
              menu_state_reader.respond_to?(:prepaginate_active) && menu_state_reader.prepaginate_active == true
            end

            def toast_label
              parts = ["#{Ansi::BRIGHT_CYAN}#{Spinner.glyph}#{Ansi::RESET}", "#{COLOR_TEXT_DIM}#{LABEL}"]
              parts << count_suffix
              "#{parts.compact.join(' ')}#{Ansi::RESET}"
            end

            def count_suffix
              total = menu_state_reader.prepaginate_total.to_i
              return nil unless total.positive?

              done = menu_state_reader.prepaginate_done.to_i.clamp(0, total)
              "#{done}/#{total}"
            end
          end
        end
      end
    end
  end
end
