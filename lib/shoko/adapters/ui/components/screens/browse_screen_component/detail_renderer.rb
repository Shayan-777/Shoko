# frozen_string_literal: true

require_relative '../../../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Detail-panel rendering for the selected browse result.
          module BrowseScreenComponentDetailRenderer
            UI = Adapters::Ui::Constants::Ui

            private

            def render_selection_details(surface, bounds, panel)
              return unless panel

              book = selected_book
              return render_empty_selection(surface, bounds, panel) unless book

              context = { surface: surface, bounds: bounds, panel: panel }
              detail = selected_book_detail(panel, book)
              row = write_detail_title(context, detail)
              row = write_detail_author(context, detail, row)
              write_detail_lines(context, detail[:lines], row)
            end

            def render_empty_selection(surface, bounds, panel)
              surface.write(bounds,
                            panel.y,
                            panel.x,
                            "#{UI::COLOR_TEXT_DIM}No book selected#{Shoko::Shared::Terminal::Ansi::RESET}")
            end

            def selected_book_detail(panel, book)
              path = book['path']
              meta = safe_metadata_for(path)
              {
                title: display_title(meta_title: meta_value(meta, :title), fallback_name: book['name']),
                author: display_author(meta, book),
                lines: detail_lines(book, panel.width),
              }
            end

            def write_detail_title(context, detail)
              title_style = "#{Shoko::Shared::Terminal::Ansi::BOLD}#{UI::COLOR_TEXT_ACCENT}"
              write_wrapped_detail(context, context[:panel].y, detail[:title], style: title_style)
            end

            def write_detail_author(context, detail, row)
              panel = context[:panel]
              return row + 1 if detail[:author].empty? || row > panel.bottom

              context[:surface].write(context[:bounds],
                                      row,
                                      panel.x,
                                      "#{UI::COLOR_TEXT_DIM}#{detail[:author]}#{Shoko::Shared::Terminal::Ansi::RESET}")
              row + 2
            end

            def write_detail_lines(context, lines, start_row)
              panel = context[:panel]
              row = start_row
              lines.each do |line|
                break if row > panel.bottom

                context[:surface].write(context[:bounds],
                                        row,
                                        panel.x,
                                        "#{UI::COLOR_TEXT_PRIMARY}#{line}#{Shoko::Shared::Terminal::Ansi::RESET}")
                row += 1
              end
            end

            def write_wrapped_detail(context, row, text, style:)
              panel = context[:panel]
              wrap_text(text, panel.width).each do |line|
                break if row > panel.bottom

                context[:surface].write(context[:bounds],
                                        row,
                                        panel.x,
                                        "#{style}#{line}#{Shoko::Shared::Terminal::Ansi::RESET}")
                row += 1
              end
              row
            end

            def detail_lines(book, width)
              lines = []
              append_detail(lines, 'Size', format_size(book['size'] || @catalog.size_for(book['path'])), width)
              append_detail(lines, 'Format', file_format(book['path']), width)
              append_detail(lines, 'File', File.basename(book['path'].to_s), width)
              lines << ''
              lines << "#{UI::COLOR_TEXT_DIM}Enter opens the selected book#{Shoko::Shared::Terminal::Ansi::RESET}"
              lines
            end

            def append_detail(lines, label, value, width)
              safe_value = sanitize_text(value)
              safe_value = '—' if safe_value.empty?
              value_width = [width - BrowseScreenComponent::DETAIL_KEY_WIDTH - 1, 8].max
              wrap_text(safe_value, value_width).each_with_index do |part, index|
                key = if index.zero?
                        pad_right("#{label}:", BrowseScreenComponent::DETAIL_KEY_WIDTH)
                      else
                        ' ' * BrowseScreenComponent::DETAIL_KEY_WIDTH
                      end
                lines << "#{key}#{truncate_text(part, value_width)}"
              end
            end

            def file_format(path)
              extension = File.extname(path.to_s).delete('.').upcase
              extension.empty? ? 'BOOK' : extension
            end
          end
        end
      end
    end
  end
end
