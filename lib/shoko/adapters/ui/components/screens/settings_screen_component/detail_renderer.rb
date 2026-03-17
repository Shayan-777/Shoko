# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          module SettingsScreenComponentDetailRenderer
            private

            def render_selection_details(surface, bounds, panel, item, value_text, value_color)
              return unless panel && item

              detail = SettingsScreenComponent::SETTING_DETAILS.fetch(item.action, SettingsScreenComponent::EMPTY_SETTING_DETAIL)
              row = panel.y
              row = render_selection_title(surface, bounds, panel, row, item.label)
              row = render_current_value(surface, bounds, panel, row, value_text, value_color)
              row = write_wrapped_block(surface, bounds, panel, row, detail.fetch(:description, ''), self.class::COLOR_TEXT_PRIMARY)
              row = render_options_detail(surface, bounds, panel, row, detail[:options])
              render_controls_detail(surface, bounds, panel, row, detail[:controls])
            end

            def render_selection_title(surface, bounds, panel, row, title)
              wrap_text(title.to_s, panel.width).each do |line|
                break if row > panel.bottom

                surface.write(bounds, row, panel.x, selection_title_text(line))
                row += 1
              end
              row
            end

            def render_current_value(surface, bounds, panel, row, value_text, value_color)
              return row if row > panel.bottom

              surface.write(bounds, row, panel.x, dim_text('Current'))
              row += 1
              return row if row > panel.bottom

              surface.write(bounds, row, panel.x, colorized_text(value_color, value_text))
              row + 2
            end

            def render_options_detail(surface, bounds, panel, row, options)
              return row unless options && row <= panel.bottom

              row += 1
              row = write_label(surface, bounds, panel, row, 'Options')
              write_wrapped_block(surface, bounds, panel, row, Array(options).join(' • '), self.class::COLOR_TEXT_DIM)
            end

            def render_controls_detail(surface, bounds, panel, row, controls)
              return row unless controls && row <= panel.bottom

              row += 1
              row = write_label(surface, bounds, panel, row, 'Controls')
              write_wrapped_block(surface, bounds, panel, row, controls, self.class::COLOR_TEXT_DIM)
            end

            def write_label(surface, bounds, panel, row, text)
              return row if row > panel.bottom

              surface.write(bounds, row, panel.x, dim_text(text.upcase))
              row + 1
            end

            def write_wrapped_block(surface, bounds, panel, row, text, color)
              wrap_text(text.to_s, panel.width).each do |line|
                break if row > panel.bottom

                surface.write(bounds, row, panel.x, "#{color}#{line}#{Shoko::Shared::Terminal::Ansi::RESET}")
                row += 1
              end
              row
            end

            def selection_title_text(text)
              colorized_text(
                "#{Shoko::Shared::Terminal::Ansi::BOLD}#{self.class::COLOR_TEXT_ACCENT}",
                text
              )
            end

            def dim_text(text)
              colorized_text(self.class::COLOR_TEXT_DIM, text)
            end

            def colorized_text(color, text)
              "#{color}#{text}#{Shoko::Shared::Terminal::Ansi::RESET}"
            end
          end
        end
      end
    end
  end
end
