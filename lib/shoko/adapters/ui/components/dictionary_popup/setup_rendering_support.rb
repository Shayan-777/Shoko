# frozen_string_literal: true

require_relative '../../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        module DictionaryPopup
          # Rendering helpers for dictionary popup setup mode.
          module SetupRenderingSupport
            include Adapters::Ui::Constants::Ui

            private

            def render_setup_panel(surface, bounds, layout)
              bg = panel_bg

              layout.height.times do |offset|
                surface.write(bounds, layout.origin_y + offset, layout.origin_x, "#{bg}#{' ' * layout.width}#{reset}")
              end

              context = setup_render_context(layout)
              lines = build_setup_lines(context[:width])
              render_setup_content_lines(surface, bounds, context, lines)
              render_setup_empty_lines(surface, bounds, context, lines.length)
              render_setup_footer(surface, bounds, layout, context)
            end

            def build_setup_lines(width)
              lines = []
              lines << setup_header_line(width)
              lines << divider_line(width)
              lines << ''
              lines << setup_word_line(width)
              lines << setup_pair_line
              lines << ''
              lines.concat(setup_prompt_lines(width))
              append_setup_stage_lines(lines, width)
              append_setup_status_lines(lines, width)
              lines
            end

            def append_setup_stage_lines(lines, width)
              if editable_setup_stage?
                lines << ''
                lines << setup_input_line(width)
                suggestion_lines = setup_suggestion_lines(width)
                lines << '' unless suggestion_lines.empty?
                lines.concat(suggestion_lines)
              elsif setup_stage == :downloading
                lines << ''
                lines << style_text('Install Progress', color: COLOR_TEXT_DIM)
                lines << setup_progress_line(width)
              end
            end

            def append_setup_status_lines(lines, width)
              status_lines = setup_status_lines(width)
              lines << '' unless status_lines.empty?
              lines.concat(status_lines)
            end

            def setup_header_line(width)
              title = style_text('Dictionary Lookup', color: COLOR_TEXT_ACCENT, bold: true)
              stage = setup_stage_meta
              badge = style_text(stage[:label], color: stage[:color], bold: true)
              align_left_right(title, badge, width)
            end

            def setup_stage_meta
              case setup_stage
              when :prompt_source
                { label: 'Step 1/2', color: COLOR_TEXT_WARNING }
              when :prompt_target
                { label: 'Step 2/2', color: COLOR_TEXT_ACCENT }
              when :downloading
                { label: 'Installing', color: COLOR_TEXT_SUCCESS }
              else
                { label: 'Setup', color: COLOR_TEXT_DIM }
              end
            end

            def setup_word_line(width)
              query = @setup_state[:query].to_s.strip
              query = '(empty selection)' if query.empty?
              content = "#{style_text('Word', color: COLOR_TEXT_DIM)}  #{style_text(query, bold: true)}"
              card_line(content, width: width, active: false)
            end

            def setup_pair_line
              source_chip = language_chip(setup_source, active: setup_stage == :prompt_source)
              target_chip = language_chip(setup_target, active: setup_stage == :prompt_target)
              arrow = style_text('->', color: COLOR_TEXT_DIM)
              "#{style_text('Pair', color: COLOR_TEXT_DIM)}  #{source_chip} #{arrow} #{target_chip}"
            end

            def setup_prompt_lines(width)
              prompt = @setup_state[:prompt].to_s.strip
              return [] if prompt.empty?

              [style_text('Prompt', color: COLOR_TEXT_DIM)]
              wrap_plain(prompt, width).map { |line| style_text(line, color: COLOR_TEXT_SECONDARY) }
            end

            def setup_input_line(width)
              label = setup_stage == :prompt_source ? 'Source' : 'Target'
              value = setup_input
              body = if value.empty?
                       "#{style_text('type language (e.g. en, de)', color: COLOR_TEXT_DIM)}" \
                         "#{style_text('_', color: COLOR_TEXT_ACCENT)}"
                     else
                       "#{style_text(value, bold: true)}#{style_text('_', color: COLOR_TEXT_ACCENT)}"
                     end
              content = "#{style_text("#{label}>", color: COLOR_TEXT_ACCENT, bold: true)} #{body}"
              card_line(content, width: width, active: true)
            end

            def setup_suggestion_lines(width)
              items = setup_suggestions
              return [] if items.empty?

              lines = [style_text('Suggestions', color: COLOR_TEXT_DIM)]
              lines.concat(pack_inline_segments(setup_suggestion_chips(items), width))
              label_line = setup_selected_suggestion_line(items[setup_suggestion_index])
              lines << label_line if label_line
              lines
            end

            def setup_suggestion_chips(items)
              items.each_with_index.map do |item, idx|
                selected = idx == setup_suggestion_index
                chip_text = "[#{item[:code].to_s.upcase}]"
                style_text(chip_text, color: selected ? COLOR_TEXT_ACCENT : COLOR_TEXT_SECONDARY, bold: selected)
              end
            end

            def setup_selected_suggestion_line(selected)
              return nil unless selected

              label = selected[:label].to_s.strip
              return nil if label.empty?

              "#{style_text('Selected', color: COLOR_TEXT_DIM)} " \
                "#{style_text(selected[:code].to_s.upcase, color: COLOR_TEXT_ACCENT, bold: true)} " \
                "#{style_text("- #{label}", color: COLOR_TEXT_SECONDARY)}"
            end

            def setup_progress_line(width)
              progress = @setup_state[:progress].to_f.clamp(0.0, 1.0)
              bar_width = [width, 10].max
              filled = (bar_width * progress).round
              empty = [bar_width - filled, 0].max

              "#{style_text('━' * filled, color: COLOR_TEXT_ACCENT)}" \
                "#{style_text('━' * empty, color: COLOR_TEXT_DIM)}"
            end

            def setup_status_lines(width)
              message = @setup_state[:status].to_s.strip
              return [] if message.empty?

              color, prefix = status_style(@setup_state[:status_level])
              text_width = [width - prefix.length - 1, 8].max
              wrap_plain(message, text_width).each_with_index.map do |line, idx|
                style_text(status_line(prefix, line, idx), color: color)
              end
            end

            def status_style(level)
              return [COLOR_TEXT_ERROR, '[!]'] if level == :error
              return [COLOR_TEXT_SUCCESS, '[ok]'] if level == :success

              [COLOR_TEXT_DIM, '[i]']
            end

            def status_line(prefix, line, idx)
              return "#{prefix} #{line}" if idx.zero?

              "#{' ' * (prefix.length + 1)}#{line}"
            end

            def render_setup_footer(surface, bounds, layout, context)
              footer_row = layout.origin_y + layout.height - 1
              padded = pad_line(setup_footer_hints, context[:width])
              surface.write(bounds, footer_row, context[:x], padded)
            end

            def setup_footer_hints
              return "#{style_text('Esc', color: COLOR_TEXT_DIM)} close" if setup_stage == :downloading

              base = "#{style_text('Type', color: COLOR_TEXT_DIM)} edit  " \
                     "#{style_text('↑↓', color: COLOR_TEXT_DIM)} pick  " \
                     "#{style_text('Tab', color: COLOR_TEXT_DIM)} apply  " \
                     "#{style_text('Enter', color: COLOR_TEXT_DIM)} continue"
              return "#{base}  #{style_text('Esc', color: COLOR_TEXT_DIM)} cancel" unless swap_hint_visible?

              "#{base}  #{style_text('S', color: COLOR_TEXT_DIM)} swap  " \
                "#{style_text('Esc', color: COLOR_TEXT_DIM)} cancel"
            end

            def swap_hint_visible?
              setup_stage == :prompt_target && !setup_source.empty?
            end
          end
        end
      end
    end
  end
end
