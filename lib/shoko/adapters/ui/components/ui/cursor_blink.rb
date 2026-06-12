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
            CursorRenderState = Struct.new(:output, :active_style, :visible_col, :inserted)
            CursorStyle = Data.define(:prefix, :restore)

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

              state = CursorRenderState.new(+'', +'', 0, false)
              target = [column.to_i, 0].max
              cursor_style = CursorStyle.new(prefix: style_prefix, restore: restore_prefix)

              styled_text.to_s.scan(Shoko::Shared::Terminal::TextMetrics::TOKEN_REGEX).each do |token|
                consume_cursor_token(state, token, target, cursor_style)
              end

              append_cursor_glyph(state, cursor_style) unless state.inserted
              Shoko::Shared::Terminal::TextMetrics.truncate_to(state.output, width_i)
            end

            private

            def consume_cursor_token(state, token, target, cursor_style)
              append_cursor_glyph(state, cursor_style) if !state.inserted && state.visible_col >= target

              state.output << token
              return update_style_state(state, token) if ansi_token?(token)
              return if token == "\e"

              state.visible_col += Shoko::Shared::Terminal::TextMetrics.display_width_for(token)
            end

            def append_cursor_glyph(state, cursor_style)
              state.output << styled_cursor_glyph(cursor_style.prefix, state.active_style, cursor_style.restore)
              state.inserted = true
            end

            def ansi_token?(token)
              token.start_with?("\e[")
            end

            def update_style_state(state, token)
              return unless token.end_with?('m')

              if token == Shoko::Shared::Terminal::Ansi::RESET
                state.active_style.clear
              else
                state.active_style << token
              end
            end

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
