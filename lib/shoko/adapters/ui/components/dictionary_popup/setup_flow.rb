# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module DictionaryPopup
          # Setup-state machine and setup rendering/key handling.
          module SetupFlow
            include Adapters::Ui::Constants::Ui

            def show_setup(stage:, query:, source_lang: nil, target_lang: nil, input_value: '', prompt: nil,
                           status: nil, status_level: nil, progress: 0.0,
                           suggestions: nil, suggestion_index: 0)
              @visible = true
              @result = nil
              @scroll_offset = 0
              @formatted_lines = []
              @entry_index = 0
              @fuzzy_mode = false
              @fuzzy_matches = []
              @setup_mode = true
              @setup_state = {
                stage: stage&.to_sym || :prompt_target,
                query: query.to_s,
                source_lang: source_lang,
                target_lang: target_lang,
                input_value: input_value.to_s,
                prompt: prompt.to_s,
                status: status.to_s,
                status_level: status_level&.to_sym,
                progress: progress.to_f,
                suggestions: normalize_setup_suggestions(suggestions),
                suggestion_index: suggestion_index.to_i,
              }
              clamp_setup_suggestion_index!
            end

            def update_setup(stage: nil, source_lang: nil, target_lang: nil, input_value: nil, prompt: nil,
                             status: nil, status_level: nil, progress: nil,
                             suggestions: nil, suggestion_index: nil)
              return unless @setup_mode

              @setup_state[:stage] = stage.to_sym if stage
              @setup_state[:source_lang] = source_lang unless source_lang.nil?
              @setup_state[:target_lang] = target_lang unless target_lang.nil?
              @setup_state[:input_value] = input_value.to_s unless input_value.nil?
              @setup_state[:prompt] = prompt.to_s unless prompt.nil?
              @setup_state[:status] = status.to_s unless status.nil?
              @setup_state[:status_level] = status_level.to_sym if status_level
              @setup_state[:progress] = progress.to_f unless progress.nil?
              @setup_state[:suggestions] = normalize_setup_suggestions(suggestions) unless suggestions.nil?
              @setup_state[:suggestion_index] = suggestion_index.to_i unless suggestion_index.nil?
              clamp_setup_suggestion_index!
            end

            def setup_mode?
              @setup_mode
            end

            def handle_setup_key(key)
              if Shared::KeyDefinitions::ACTIONS[:cancel].include?(key) ||
                 Shared::KeyDefinitions::ACTIONS[:quit].include?(key)
                return { type: :close }
              end

              if Shared::KeyDefinitions::NAVIGATION[:up].include?(key)
                return emit_setup_selection(-1)
              elsif Shared::KeyDefinitions::NAVIGATION[:down].include?(key)
                return emit_setup_selection(1)
              end

              return nil if setup_stage == :downloading

              if key == "\t"
                suggestion = selected_setup_suggestion_code
                if suggestion
                  update_setup_input(suggestion)
                  return { type: :setup_apply_suggestion, stage: setup_stage, value: suggestion }
                end
                return nil
              end

              if key == 'S' && setup_stage == :prompt_target && !setup_source.empty?
                return { type: :setup_swap }
              end

              if Shared::KeyDefinitions::ACTIONS[:confirm].include?(key)
                return { type: :setup_submit, stage: setup_stage, value: setup_input }
              end

              return nil unless editable_setup_stage?

              if Shared::KeyDefinitions::ACTIONS[:backspace].include?(key)
                update_setup_input(setup_input[0...-1].to_s)
                return { type: :setup_change, stage: setup_stage, value: setup_input }
              end

              return nil unless printable_input_char?(key)

              update_setup_input("#{setup_input}#{key}")
              { type: :setup_change, stage: setup_stage, value: setup_input }
            end

            def render_setup_panel(surface, bounds, layout)
              bg = panel_bg

              layout.height.times do |offset|
                surface.write(bounds, layout.origin_y + offset, layout.origin_x,
                              "#{bg}#{' ' * layout.width}#{reset}")
              end

              padding_h = self.class::PADDING_H
              padding_v = self.class::PADDING_V
              content_x = layout.origin_x + padding_h
              content_width = [layout.width - (padding_h * 2), 10].max
              content_y = layout.origin_y + padding_v
              content_height = [layout.height - (padding_v * 2) - 1, 1].max
              @last_content_height = content_height

              lines = build_setup_lines(content_width)
              visible_lines = lines.first(content_height)
              visible_lines.each_with_index do |line, idx|
                row = content_y + idx
                surface.write(bounds, row, content_x, pad_line(line.to_s, content_width))
              end

              remaining = [content_height - visible_lines.length, 0].max
              empty_line = pad_line('', content_width)
              remaining.times do |i|
                row = content_y + visible_lines.length + i
                surface.write(bounds, row, content_x, empty_line)
              end

              render_setup_footer(surface, bounds, layout, content_x, content_width)
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

              status_lines = setup_status_lines(width)
              lines << '' unless status_lines.empty?
              lines.concat(status_lines)

              lines
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

              lines = [style_text('Prompt', color: COLOR_TEXT_DIM)]
              wrap_plain(prompt, width).each do |line|
                lines << style_text(line, color: COLOR_TEXT_SECONDARY)
              end
              lines
            end

            def setup_input_line(width)
              label = setup_stage == :prompt_source ? 'Source' : 'Target'
              value = setup_input
              body = if value.empty?
                       "#{style_text('type language (e.g. en, de)', color: COLOR_TEXT_DIM)}#{style_text('_', color: COLOR_TEXT_ACCENT)}"
                     else
                       "#{style_text(value, bold: true)}#{style_text('_', color: COLOR_TEXT_ACCENT)}"
                     end
              content = "#{style_text("#{label}>", color: COLOR_TEXT_ACCENT, bold: true)} #{body}"
              card_line(content, width: width, active: true)
            end

            def setup_suggestion_lines(width)
              items = setup_suggestions
              return [] if items.empty?

              chips = items.each_with_index.map do |item, idx|
                selected = idx == setup_suggestion_index
                chip_text = "[#{item[:code].to_s.upcase}]"
                style_text(chip_text, color: selected ? COLOR_TEXT_ACCENT : COLOR_TEXT_SECONDARY, bold: selected)
              end
              lines = [style_text('Suggestions', color: COLOR_TEXT_DIM)]
              lines.concat(pack_inline_segments(chips, width))
              selected = items[setup_suggestion_index]
              if selected
                label = selected[:label].to_s.strip
                unless label.empty?
                  lines << "#{style_text('Selected', color: COLOR_TEXT_DIM)} " \
                           "#{style_text(selected[:code].to_s.upcase, color: COLOR_TEXT_ACCENT, bold: true)} " \
                           "#{style_text("- #{label}", color: COLOR_TEXT_SECONDARY)}"
                end
              end
              lines
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

              level = @setup_state[:status_level]
              color = case level
                      when :error then COLOR_TEXT_ERROR
                      when :success then COLOR_TEXT_SUCCESS
                      else COLOR_TEXT_DIM
                      end
              prefix = case level
                       when :error then '[!]'
                       when :success then '[ok]'
                       else '[i]'
                       end

              text_width = [width - prefix.length - 1, 8].max
              wrapped = wrap_plain(message, text_width)
              wrapped.each_with_index.map do |line, idx|
                stem = idx.zero? ? "#{prefix} #{line}" : "#{' ' * (prefix.length + 1)}#{line}"
                style_text(stem, color: color)
              end
            end

            def render_setup_footer(surface, bounds, layout, content_x, content_width)
              footer_row = layout.origin_y + layout.height - 1
              hints = if setup_stage == :downloading
                        "#{style_text('Esc', color: COLOR_TEXT_DIM)} close"
                      else
                        base = "#{style_text('Type', color: COLOR_TEXT_DIM)} edit  " \
                               "#{style_text('↑↓', color: COLOR_TEXT_DIM)} pick  " \
                               "#{style_text('Tab', color: COLOR_TEXT_DIM)} apply  " \
                               "#{style_text('Enter', color: COLOR_TEXT_DIM)} continue"
                        if setup_stage == :prompt_target && !setup_source.empty?
                          "#{base}  #{style_text('S', color: COLOR_TEXT_DIM)} swap  " \
                            "#{style_text('Esc', color: COLOR_TEXT_DIM)} cancel"
                        else
                          "#{base}  #{style_text('Esc', color: COLOR_TEXT_DIM)} cancel"
                        end
                      end
              padded = pad_line(hints, content_width)
              surface.write(bounds, footer_row, content_x, padded)
            end

            def divider_line(width)
              style_text('─' * width, color: COLOR_TEXT_DIM)
            end

            def align_left_right(left, right, width)
              left_len = visible_length(left)
              right_len = visible_length(right)
              padding = width - left_len - right_len
              return "#{left}#{' ' * padding}#{right}" if padding >= 1

              truncated_left = truncate_visible(left, [width - right_len - 1, 1].max)
              gap = [width - visible_length(truncated_left) - right_len, 1].max
              "#{truncated_left}#{' ' * gap}#{right}"
            end

            def truncate_visible(text, width)
              Shared::Terminal::TextMetrics.truncate_to(text.to_s, width.to_i)
            rescue StandardError
              Ui::TextUtils.truncate_text(text.to_s.gsub(/\e\[[0-9;]*m/, ''), width)
            end

            def language_chip(value, active:)
              lang = value.to_s.strip
              label = lang.empty? ? '--' : lang.upcase
              color = if lang.empty?
                        COLOR_TEXT_DIM
                      elsif active
                        COLOR_TEXT_ACCENT
                      else
                        COLOR_TEXT_PRIMARY
                      end
              style_text("[#{label}]", color: color, bold: active && !lang.empty?)
            end

            def pack_inline_segments(segments, width, gap: '  ')
              out = []
              current = ''
              Array(segments).each do |segment|
                next if segment.to_s.empty?

                candidate = current.empty? ? segment.to_s : "#{current}#{gap}#{segment}"
                if visible_length(candidate) <= width
                  current = candidate
                else
                  out << current unless current.empty?
                  current = segment.to_s
                end
              end
              out << current unless current.empty?
              out
            end

            def setup_stage
              (@setup_state[:stage] || :prompt_target).to_sym
            end

            def setup_source
              @setup_state[:source_lang].to_s.strip
            end

            def setup_target
              @setup_state[:target_lang].to_s.strip
            end

            def setup_input
              @setup_state[:input_value].to_s
            end

            def setup_suggestions
              normalize_setup_suggestions(@setup_state[:suggestions])
            end

            def setup_suggestion_index
              clamp_setup_suggestion_index!
              @setup_state[:suggestion_index].to_i
            end

            def selected_setup_suggestion
              items = setup_suggestions
              return nil if items.empty?

              items[setup_suggestion_index]
            end

            def selected_setup_suggestion_code
              selected_setup_suggestion&.dig(:code).to_s
            end

            def editable_setup_stage?
              %i[prompt_source prompt_target].include?(setup_stage)
            end

            def update_setup_input(value)
              @setup_state[:input_value] = value.to_s
            end

            def emit_setup_selection(delta)
              return nil unless editable_setup_stage?

              items = setup_suggestions
              return nil if items.empty?

              index = setup_suggestion_index
              index = (index + delta.to_i) % items.length
              @setup_state[:suggestion_index] = index
              { type: :setup_select, stage: setup_stage, index: index, value: items[index][:code] }
            end

            def normalize_setup_suggestions(items)
              Array(items).filter_map do |item|
                if item.is_a?(Hash)
                  code = item[:code] || item['code']
                  label = item[:label] || item['label'] || code
                  code_text = code.to_s.strip.downcase
                  next if code_text.empty?

                  { code: code_text, label: label.to_s.strip }
                else
                  code_text = item.to_s.strip.downcase
                  next if code_text.empty?

                  { code: code_text, label: code_text.upcase }
                end
              end.uniq { |entry| entry[:code] }
            end

            def clamp_setup_suggestion_index!
              items = setup_suggestions
              max = [items.length - 1, 0].max
              idx = @setup_state[:suggestion_index].to_i
              idx = 0 if idx.negative?
              idx = max if idx > max
              @setup_state[:suggestion_index] = idx
            end

            def printable_input_char?(key)
              return false unless key.is_a?(String)
              return false unless key.length == 1

              codepoint = key.ord
              codepoint >= 32 && codepoint != 127
            rescue StandardError
              false
            end

            def wrap_plain(text, width)
              text.to_s.split("\n").flat_map { |line| wrap_line(line, width) }
            end

            def wrap_line(text, width)
              return [''] if text.nil?
              return [text.to_s] if visible_length(text) <= width

              words = text.to_s.split(/\s+/)
              lines = []
              current = ''
              words.each do |word|
                if current.empty?
                  current = word
                  next
                end

                candidate = "#{current} #{word}"
                if visible_length(candidate) <= width
                  current = candidate
                else
                  lines << current
                  current = word
                end
              end
              lines << current unless current.empty?
              lines
            end
          end
        end
      end
    end
  end
end
