# frozen_string_literal: true

require_relative '../../../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Detail-panel rendering helpers for cached library entries.
          module LibraryScreenComponentDetailRenderer
            UI = Adapters::Ui::Constants::Ui

            private

            def render_details_panel(surface, bounds, context)
              panel = context[:panel]
              item = context[:item]
              return unless panel && item

              row = panel.y
              details_lines(item, context[:selected], context[:total], panel.width).each do |line|
                break if row > panel.bottom

                text = "#{UI::COLOR_TEXT_PRIMARY}#{line}#{Shoko::Shared::Terminal::Ansi::RESET}"
                surface.write(bounds, row, panel.x, text)
                row += 1
              end
            end

            def details_lines(item, selected, total, inner_width)
              title_lines(item, selected, total, inner_width) + detail_lines(item, inner_width)
            end

            def title_lines(item, selected, total, inner_width)
              title = safe_text(item.title || 'Untitled')
              wrap_text(title, inner_width).map do |line|
                "#{Shoko::Shared::Terminal::Ansi::BOLD}#{UI::COLOR_TEXT_ACCENT}#{line}#{Shoko::Shared::Terminal::Ansi::RESET}"
              end + ["#{UI::COLOR_TEXT_DIM}Book #{selected + 1} of #{total}#{Shoko::Shared::Terminal::Ansi::RESET}", '']
            end

            def detail_lines(item, inner_width)
              lines = []
              append_detail(lines, 'Authors', item.authors, inner_width)
              append_detail(lines, 'Year', item.year, inner_width)
              append_detail(lines, 'Accessed', relative_accessed_label(item.last_accessed), inner_width)
              append_detail(lines, 'Size', format_size(item.size_bytes), inner_width)
              append_detail(lines, 'Cache', compact_path(item.open_path), inner_width)
              append_detail(lines, 'EPUB', compact_path(item.epub_path), inner_width)
              lines
            end

            def append_detail(lines, label, value, width)
              safe_value = safe_text(value.to_s.strip)
              safe_value = '—' if safe_value.empty?
              value_width = [width - LibraryScreenComponent::DETAIL_KEY_WIDTH - 1, 8].max
              wrapped = wrap_text(safe_value, value_width)
              wrapped = ['—'] if wrapped.empty?
              wrapped.each_with_index do |part, index|
                key = if index.zero?
                        pad_right("#{label}:", LibraryScreenComponent::DETAIL_KEY_WIDTH)
                      else
                        ' ' * LibraryScreenComponent::DETAIL_KEY_WIDTH
                      end
                lines << "#{key}#{truncate_text(part, value_width)}"
              end
            end

            def compact_path(path)
              value = path.to_s
              return '—' if value.empty?

              safe_text(File.basename(value))
            end

            def format_size(bytes)
              format('%.1f MB', (bytes.to_f / (1024 * 1024)).round(1))
            end

            def relative_accessed_label(iso)
              return '' unless iso

              seconds = time_elapsed_seconds(iso)
              seconds ? format_relative_time(seconds) : ''
            end

            def time_elapsed_seconds(iso)
              (Time.now - Time.parse(iso)).to_i
            end

            def format_relative_time(seconds)
              return 'a minute ago' if seconds < 60

              interval = LibraryScreenComponent::TIME_INTERVALS.find { |entry| seconds < entry[:max] }
              value = [seconds / interval[:div], 1].max
              value == 1 ? interval[:singular] : format(interval[:plural], value)
            end
          end
        end
      end
    end
  end
end
