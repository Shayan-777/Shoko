# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Detail-panel rendering helpers for the selected settings item.
          module SettingsScreenComponentDetailRenderer
            private

            def render_selection_details(context, selection)
              panel = context[:panel]
              item = selection[:item]
              return unless panel && item

              detail = selection_detail(item.action)
              row = panel.y
              row = render_selection_title(context, row, item.label)
              row = render_current_value(context, row, selection[:value_text], selection[:value_color])
              row = write_wrapped_block(context, row, detail.fetch(:description, ''), self.class::COLOR_TEXT_PRIMARY)
              row = render_options_detail(context, row, detail[:options])
              render_controls_detail(context, row, detail[:controls])
            end

            def selection_detail(action)
              SettingsScreenComponent::SETTING_DETAILS.fetch(action, SettingsScreenComponent::EMPTY_SETTING_DETAIL)
            end

            def render_selection_title(context, row, title)
              panel = context[:panel]
              wrap_text(title.to_s, panel.width).each do |line|
                break if row > panel.bottom

                write_detail_text(context, row, selection_title_text(line))
                row += 1
              end
              row
            end

            def render_current_value(context, row, value_text, value_color)
              panel = context[:panel]
              return row if row > panel.bottom

              write_detail_text(context, row, dim_text('Current'))
              row += 1
              return row if row > panel.bottom

              write_detail_text(context, row, colorized_text(value_color, value_text))
              row + 2
            end

            def render_options_detail(context, row, options)
              panel = context[:panel]
              return row unless options && row <= panel.bottom

              row += 1
              row = write_label(context, row, 'Options')
              write_wrapped_block(context, row, Array(options).join(' • '), self.class::COLOR_TEXT_DIM)
            end

            def render_controls_detail(context, row, controls)
              panel = context[:panel]
              return row unless controls && row <= panel.bottom

              row += 1
              row = write_label(context, row, 'Controls')
              write_wrapped_block(context, row, controls, self.class::COLOR_TEXT_DIM)
            end

            def write_label(context, row, text)
              panel = context[:panel]
              return row if row > panel.bottom

              write_detail_text(context, row, dim_text(text.upcase))
              row + 1
            end

            def write_wrapped_block(context, row, text, color)
              panel = context[:panel]
              wrap_text(text.to_s, panel.width).each do |line|
                break if row > panel.bottom

                write_detail_text(context, row, "#{color}#{line}#{Shoko::Shared::Terminal::Ansi::RESET}")
                row += 1
              end
              row
            end

            def write_detail_text(context, row, text)
              panel = context[:panel]
              context[:surface].write(context[:bounds], row, panel.x, text)
            end

            def selection_title_text(text)
              colorized_text("#{Shoko::Shared::Terminal::Ansi::BOLD}#{self.class::COLOR_TEXT_ACCENT}", text)
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
