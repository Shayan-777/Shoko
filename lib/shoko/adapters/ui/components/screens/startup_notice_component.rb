# frozen_string_literal: true

require_relative '../base_component'
require 'shoko/shared/terminal/text_metrics'
require 'shoko/shared/terminal/ansi'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Bottom-left one-line banner shown in the menu when startup had
          # something the user must know about — e.g. a schema reset archived
          # their previous config. Reads the menu's transient `startup_notice`
          # field and stays visible until the session ends.
          class StartupNoticeComponent < BaseComponent
            include Adapters::Ui::Constants::Ui

            Ansi = Shoko::Shared::Terminal::Ansi
            TextMetrics = Shoko::Shared::Terminal::TextMetrics
            PREFIX = '!'

            def initialize(menu_state_reader:)
              super()
              @menu_state_reader = menu_state_reader
            end

            def do_render(surface, bounds)
              text = notice_text
              return if text.empty?
              return if bounds.width < 12 || bounds.height < 1

              label = "#{Ansi::BRIGHT_YELLOW}#{PREFIX}#{Ansi::RESET} #{COLOR_TEXT_DIM}#{truncated(text, bounds)}#{Ansi::RESET}"
              surface.write(bounds, bounds.height, 1, label)
            end

            private

            attr_reader :menu_state_reader

            def notice_text
              menu_state_reader.startup_notice.to_s.strip
            end

            def truncated(text, bounds)
              TextMetrics.truncate_to(text, [bounds.width - 3, 1].max)
            end
          end
        end
      end
    end
  end
end
