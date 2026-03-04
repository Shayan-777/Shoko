# frozen_string_literal: true

require_relative '../../../../shared/terminal/ansi'
require_relative '../../../../shared/terminal/text_metrics'

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          # Shared cursor blinking behavior for text editors.
          module CursorBlink
            BLINK_IDLE_AFTER = 0.7
            BLINK_PERIOD = 1.0
            CURSOR_GLYPH = begin
              ascii_icons = %w[1 true yes on].include?(ENV.fetch('SHOKO_ASCII_ICONS', '').to_s.strip.downcase)
              ascii_icons ? '|' : '▏'
            end

            def initialize_cursor_blink
              @cursor_last_input_at = monotonic_time
            end

            def record_cursor_activity
              @cursor_last_input_at = monotonic_time
            end

            def cursor_visible?
              cursor_state.first
            end

            def cursor_glyph
              cursor_state.last
            end

            def cursor_state(now = monotonic_time)
              last = @cursor_last_input_at || now
              elapsed = now - last
              return [true, CURSOR_GLYPH] if elapsed < BLINK_IDLE_AFTER

              phase = (elapsed - BLINK_IDLE_AFTER) % BLINK_PERIOD
              visible = phase < (BLINK_PERIOD / 2.0)
              [visible, visible ? CURSOR_GLYPH : ' ']
            end

            def inline_cursor_text(styled_text, column, width:, style_prefix: nil, restore_prefix: nil)
              width_i = width.to_i
              return '' if width_i <= 0

              target = [column.to_i, 0].max
              source = styled_text.to_s
              output = +''
              active_style = +''
              visible_col = 0
              inserted = false

              source.scan(Shoko::Shared::Terminal::TextMetrics::TOKEN_REGEX).each do |token|
                if !inserted && visible_col >= target
                  output << styled_cursor_glyph(style_prefix, active_style, restore_prefix)
                  inserted = true
                end

                output << token
                if token.start_with?("\e[")
                  if token.end_with?('m')
                    if token == Shoko::Shared::Terminal::Ansi::RESET
                      active_style.clear
                    else
                      active_style << token
                    end
                  end
                  next
                end

                next if token == "\e"

                visible_col += Shoko::Shared::Terminal::TextMetrics.display_width_for(token)
              end

              output << styled_cursor_glyph(style_prefix, active_style, restore_prefix) unless inserted
              Shoko::Shared::Terminal::TextMetrics.truncate_to(output, width_i)
            end

            private

            def styled_cursor_glyph(style_prefix, restore_style, restore_prefix)
              visible, glyph = cursor_state
              glyph = glyph.to_s
              return glyph if glyph.empty?
              return glyph unless visible && style_prefix && !style_prefix.empty?

              restored = "#{restore_prefix}#{restore_style}"
              "#{style_prefix}#{glyph}#{restored}"
            end

            def monotonic_time
              Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end
          end
        end
      end
    end
  end
end
