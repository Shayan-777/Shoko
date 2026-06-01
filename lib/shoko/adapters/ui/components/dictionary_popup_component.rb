# frozen_string_literal: true

require_relative 'base_component'
require_relative 'render_style'
require_relative 'ui/overlay_layout'
require_relative 'ui/text_utils'
require_relative 'dictionary/entry_formatter'
require_relative '../../../shared/terminal/ansi'
require_relative '../../../shared/key_definitions'
require_relative '../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        # Popup overlay component for dictionary lookup results.
        # Dark, clean design that blends with the reader background.
        class DictionaryPopupComponent < BaseComponent
          include Adapters::Ui::Constants::Ui

          # Background colors for dark/light modes
          POPUP_BG = "\e[48;5;236m"        # Dark gray (blends with dark reader)
          POPUP_BG_LIGHT = "\e[48;5;254m"  # Light gray (blends with light reader)
          CARD_BG = "\e[48;5;238m"
          CARD_BG_LIGHT = "\e[48;5;252m"

          PADDING_H = 2
          PADDING_V = 1

          attr_reader :visible, :scroll_offset, :result, :entry_index

          def initialize(reader_state_reader: nil, color_mode: :dark)
            super()
            @reader_state_reader = reader_state_reader
            @color_mode = color_mode
            @visible = false
            @scroll_offset = 0
            @result = nil
            @formatted_lines = []
            @formatter = nil
            @entry_index = 0
            @fuzzy_mode = false
            @fuzzy_matches = []
            @setup_mode = false
            @setup_state = {}
            @overlay_sizing = Ui::OverlaySizing.new(
              width_ratio: 0.55,
              width_padding: 10,
              min_width: 42,
              height_ratio: 0.50,
              height_padding: 8,
              min_height: 10
            )
            @setup_overlay_sizing = Ui::OverlaySizing.new(
              width_ratio: 0.58,
              width_padding: 8,
              min_width: 54,
              height_ratio: 0.42,
              height_padding: 8,
              min_height: 12
            )
          end

          def show(result)
            @result = result
            @visible = true
            @scroll_offset = 0
            @formatted_lines = []
            @entry_index = 0
            @fuzzy_mode = false
            @fuzzy_matches = []
            @setup_mode = false
            @setup_state = {}
          end

          def hide
            @visible = false
            @result = nil
            @formatted_lines = []
            @scroll_offset = 0
            @entry_index = 0
            @fuzzy_mode = false
            @fuzzy_matches = []
            @setup_mode = false
            @setup_state = {}
          end

          def visible?
            @visible
          end

          def update_color_mode(mode)
            @color_mode = mode.to_s == 'light' ? :light : :dark
            @formatter = nil
            @formatted_lines = []
            @scroll_offset = 0
          end

          def scroll_up
            @scroll_offset = [@scroll_offset - 1, 0].max
          end

          def scroll_down(max_scroll = nil)
            limit = max_scroll.nil? ? max_scroll_offset : max_scroll
            @scroll_offset = [@scroll_offset + 1, limit].min
          end

          def insert_char(char)
            return nil unless @visible && @setup_mode

            handle_setup_key(char.to_s)
          end

          def backspace
            return nil unless @visible && @setup_mode

            handle_setup_key(Shared::KeyDefinitions::ACTIONS[:backspace].first)
          end

          def confirm
            return nil unless @visible
            return nil unless @setup_mode

            handle_setup_key(Shared::KeyDefinitions::ACTIONS[:confirm].first)
          end

          def cancel
            return nil unless @visible

            { type: :close }
          end

          def tab
            return nil unless @visible && @setup_mode

            handle_setup_key("\t")
          end

          def swap_languages
            return nil unless @visible && @setup_mode

            handle_setup_key('S')
          end

          def scroll_up_action
            return nil unless @visible

            if @setup_mode
              emit_setup_selection(-1)
            else
              scroll_up
              { type: :scroll }
            end
          end

          def scroll_down_action
            return nil unless @visible

            if @setup_mode
              emit_setup_selection(1)
            else
              scroll_down
              { type: :scroll }
            end
          end

          def render(surface, bounds)
            return unless @visible

            layout = overlay_layout(bounds)
            @layout = layout

            if @setup_mode
              render_setup_panel(surface, bounds, layout)
            else
              render_panel(surface, bounds, layout)
            end
          end

          def do_render(surface, bounds)
            render(surface, bounds)
          end

          def handle_key(key)
            return nil unless @visible

            return handle_setup_key(key) if @setup_mode

            if Shared::KeyDefinitions::NAVIGATION[:up].include?(key)
              scroll_up_action
            elsif Shared::KeyDefinitions::NAVIGATION[:down].include?(key)
              scroll_down_action
            elsif close_key?(key)
              cancel
            end
          end

          def handle_click(_col, _row)
            nil
          end


          include Adapters::Ui::Constants::Ui

          def show_setup(stage:, query:, source_lang: nil, target_lang: nil, input_value: '', prompt: nil,
                         status: nil, status_level: nil, progress: 0.0,
                         suggestions: nil, suggestion_index: 0)
            reset_result_mode_state!
            @setup_mode = true
            @setup_state = build_setup_state(stage: stage,
                                             query: query,
                                             source_lang: source_lang,
                                             target_lang: target_lang,
                                             input_value: input_value,
                                             prompt: prompt,
                                             status: status,
                                             status_level: status_level,
                                             progress: progress,
                                             suggestions: suggestions,
                                             suggestion_index: suggestion_index)
            clamp_setup_suggestion_index!
          end

          def update_setup(stage: nil, source_lang: nil, target_lang: nil, input_value: nil, prompt: nil,
                           status: nil, status_level: nil, progress: nil,
                           suggestions: nil, suggestion_index: nil)
            return unless @setup_mode

            updates = {
              stage: [stage, :to_sym],
              source_lang: [source_lang, nil],
              target_lang: [target_lang, nil],
              input_value: [input_value, :to_s],
              prompt: [prompt, :to_s],
              status: [status, :to_s],
              status_level: [status_level, :to_sym],
              progress: [progress, :to_f],
              suggestions: [suggestions, method(:normalize_setup_suggestions)],
              suggestion_index: [suggestion_index, :to_i],
            }
            apply_setup_updates(updates)
            clamp_setup_suggestion_index!
          end

          def setup_mode?
            @setup_mode
          end

          def handle_setup_key(key)
            return { type: :close } if close_setup_key?(key)

            navigation = setup_navigation_event(key)
            return navigation if navigation

            return nil if setup_stage == :downloading

            immediate = setup_immediate_event(key)
            return immediate if immediate

            return nil unless editable_setup_stage?

            setup_edit_event(key)
          end

          def reset_result_mode_state!
            @visible = true
            @result = nil
            @scroll_offset = 0
            @formatted_lines = []
            @entry_index = 0
            @fuzzy_mode = false
            @fuzzy_matches = []
          end

          def close_setup_key?(key)
            Shared::KeyDefinitions::ACTIONS[:cancel].include?(key) ||
              Shared::KeyDefinitions::ACTIONS[:quit].include?(key)
          end

          def setup_navigation_event(key)
            return emit_setup_selection(-1) if Shared::KeyDefinitions::NAVIGATION[:up].include?(key)
            return emit_setup_selection(1) if Shared::KeyDefinitions::NAVIGATION[:down].include?(key)

            nil
          end

          def setup_immediate_event(key)
            tab_event = setup_tab_event(key)
            return tab_event if tab_event
            return { type: :setup_swap } if setup_swap_key?(key)
            return { type: :setup_submit, stage: setup_stage, value: setup_input } if setup_confirm_key?(key)

            nil
          end

          def setup_tab_event(key)
            return nil unless key == "\t"

            suggestion = selected_setup_suggestion_code
            return nil unless suggestion

            update_setup_input(suggestion)
            { type: :setup_apply_suggestion, stage: setup_stage, value: suggestion }
          end

          def setup_swap_key?(key)
            key == 'S' && setup_stage == :prompt_target && !setup_source.empty?
          end

          def setup_confirm_key?(key)
            Shared::KeyDefinitions::ACTIONS[:confirm].include?(key)
          end

          def setup_edit_event(key)
            if Shared::KeyDefinitions::ACTIONS[:backspace].include?(key)
              update_setup_input(setup_input[0...-1].to_s)
              return { type: :setup_change, stage: setup_stage, value: setup_input }
            end

            return nil unless printable_input_char?(key)

            update_setup_input("#{setup_input}#{key}")
            { type: :setup_change, stage: setup_stage, value: setup_input }
          end

          # Rendering helpers for dictionary popup setup mode.
          include Adapters::Ui::Constants::Ui


          # Text/layout helpers for dictionary popup setup mode.
          include Adapters::Ui::Constants::Ui


          PanelContentContext = Data.define(:surface,
                                            :bounds,
                                            :content_x,
                                            :content_y,
                                            :content_width,
                                            :content_height)

          def advance_entry!
            return nil unless @result && @result.entry_count > 1
            return nil if @fuzzy_mode

            @entry_index = (@entry_index + 1) % @result.entry_count
            @formatted_lines = []
            @scroll_offset = 0
            :advanced
          end
          alias next_entry advance_entry!

          def toggle_fuzzy(matches = nil)
            if @fuzzy_mode
              @fuzzy_mode = false
              @fuzzy_matches = []
            else
              @fuzzy_mode = true
              @fuzzy_matches = Array(matches)
            end
            @formatted_lines = []
            @scroll_offset = 0
          end

          def fuzzy_mode?
            @fuzzy_mode
          end

          def render_panel(surface, bounds, layout)
            sync_from_state
            fill_panel_background(surface, bounds, layout)
            context = build_content_context(surface, bounds, layout)
            @last_content_height = context.content_height
            render_content(context)
            render_footer(surface, bounds, layout, context)
          end

          def render_content(context)
            return unless @result

            ensure_formatted_lines(context.content_width)
            render_visible_lines(context)
            fill_empty_lines(context)
            render_scroll_indicators(context)
          end

          def render_scroll_indicators(context)
            return unless @formatted_lines.length > context.content_height

            render_up_scroll_indicator(context) if @scroll_offset.positive?
            return unless more_content_below?(context)

            render_down_scroll_indicator(context)
          end

          def render_footer(surface, bounds, layout, context)
            footer_row = layout.origin_y + layout.height - 1

            dim = "\e[2m"
            nodim = "\e[22m"
            hints = "#{dim}Esc#{nodim} close  #{dim}Tab#{nodim} next  #{dim}f#{nodim} fuzzy"
            padded = pad_line(hints, context.content_width)
            surface.write(bounds, footer_row, context.content_x, padded)
          end


          private

          def close_key?(key)
            Shared::KeyDefinitions::ACTIONS[:cancel].include?(key) ||
              Shared::KeyDefinitions::ACTIONS[:quit].include?(key)
          end


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

          # State mutation and normalization helpers for dictionary popup setup mode.
          def build_setup_state(stage:, query:, source_lang:, target_lang:, input_value:, prompt:, status:,
                                status_level:, progress:, suggestions:, suggestion_index:)
            {
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
          end

          def apply_setup_updates(updates)
            updates.each do |key, payload|
              assign_setup_value(key, payload[0], payload[1])
            end
          end

          def assign_setup_value(key, value, converter = nil)
            return if value.nil?

            @setup_state[key] = convert_setup_value(value, converter)
          end

          def convert_setup_value(value, converter)
            return value unless converter
            return converter.call(value) if converter.respond_to?(:call)

            value.public_send(converter)
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
            normalized = Array(items).filter_map { |item| normalize_setup_suggestion(item) }
            normalized.uniq { |entry| entry[:code] }
          end

          def normalize_setup_suggestion(item)
            return normalize_setup_suggestion_hash(item) if item.is_a?(Hash)

            normalize_setup_suggestion_scalar(item)
          end

          def normalize_setup_suggestion_hash(item)
            normalized = item.transform_keys do |key|
              key.is_a?(String) ? key.to_sym : key
            end
            code = normalized[:code]
            label = normalized[:label] || code
            code_text = code.to_s.strip.downcase
            return nil if code_text.empty?

            { code: code_text, label: label.to_s.strip }
          end

          def normalize_setup_suggestion_scalar(item)
            code_text = item.to_s.strip.downcase
            return nil if code_text.empty?

            { code: code_text, label: code_text.upcase }
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
          rescue Shoko::Error
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
              current = append_wrapped_word(lines, current, word, width)
            end
            lines << current unless current.empty?
            lines
          end

          def append_wrapped_word(lines, current, word, width)
            return word if current.empty?

            candidate = "#{current} #{word}"
            return candidate if visible_length(candidate) <= width

            lines << current
            word
          end

          def setup_render_context(layout)
            padding_h = self.class::PADDING_H
            padding_v = self.class::PADDING_V
            width = [layout.width - (padding_h * 2), 10].max
            height = [layout.height - (padding_v * 2) - 1, 1].max
            @last_content_height = height
            {
              x: layout.origin_x + padding_h,
              y: layout.origin_y + padding_v,
              width: width,
              height: height,
            }
          end

          def render_setup_content_lines(surface, bounds, context, lines)
            visible_lines = lines.first(context[:height])
            visible_lines.each_with_index do |line, idx|
              row = context[:y] + idx
              surface.write(bounds, row, context[:x], pad_line(line.to_s, context[:width]))
            end
          end

          def render_setup_empty_lines(surface, bounds, context, rendered_count)
            remaining = [context[:height] - rendered_count, 0].max
            empty_line = pad_line('', context[:width])
            remaining.times do |idx|
              row = context[:y] + rendered_count + idx
              surface.write(bounds, row, context[:x], empty_line)
            end
          end


          # Lookup result/entry/fuzzy are observable reader view-state; pull them
          # in for the results view and invalidate the format cache on change.
          # (Setup rendering is self-owned and does not call this.)
          def sync_from_state
            return unless @reader_state_reader.respond_to?(:dictionary_result)

            result = @reader_state_reader.dictionary_result
            entry_index = @reader_state_reader.dictionary_entry_index.to_i
            fuzzy_mode = @reader_state_reader.dictionary_fuzzy_mode == true
            fuzzy_matches = Array(@reader_state_reader.dictionary_fuzzy_matches)
            return if result == @result && entry_index == @entry_index &&
                      fuzzy_mode == @fuzzy_mode && fuzzy_matches == @fuzzy_matches

            @result = result
            @entry_index = entry_index
            @fuzzy_mode = fuzzy_mode
            @fuzzy_matches = fuzzy_matches
            @formatted_lines = []
            @scroll_offset = 0
          end

          def fill_panel_background(surface, bounds, layout)
            layout.height.times do |offset|
              surface.write(bounds,
                            layout.origin_y + offset,
                            layout.origin_x,
                            "#{panel_bg}#{' ' * layout.width}#{reset}")
            end
          end

          def build_content_context(surface, bounds, layout)
            padding_h = self.class::PADDING_H
            padding_v = self.class::PADDING_V
            PanelContentContext.new(
              surface: surface,
              bounds: bounds,
              content_x: layout.origin_x + padding_h,
              content_y: layout.origin_y + padding_v,
              content_width: layout.width - (padding_h * 2),
              content_height: layout.height - (padding_v * 2) - 1
            )
          end

          def ensure_formatted_lines(content_width)
            return unless @formatted_lines.empty?

            @formatter = Dictionary::EntryFormatter.new(width: content_width,
                                                        background: panel_bg,
                                                        color_mode: @color_mode)
            @formatted_lines = if @fuzzy_mode
                                 @formatter.format_fuzzy_results(@fuzzy_matches, @result.query)
                               else
                                 @formatter.format_result(@result, entry_index: @entry_index)
                               end
          end

          def indicator_x(context)
            context.content_x + context.content_width - 1
          end

          def render_up_scroll_indicator(context)
            context.surface.write(context.bounds, context.content_y, indicator_x(context), "#{panel_bg}\e[2m▲\e[22m")
          end

          def render_down_scroll_indicator(context)
            context.surface.write(
              context.bounds,
              context.content_y + context.content_height - 1,
              indicator_x(context),
              "#{panel_bg}\e[2m▼\e[22m"
            )
          end

          def more_content_below?(context)
            @scroll_offset < @formatted_lines.length - context.content_height
          end

          def render_visible_lines(context)
            visible_lines = @formatted_lines[@scroll_offset, context.content_height] || []
            visible_lines.each_with_index do |line, index|
              row = context.content_y + index
              context.surface.write(context.bounds,
                                    row,
                                    context.content_x,
                                    pad_line(line.to_s, context.content_width))
            end
          end

          def fill_empty_lines(context)
            visible_count = (@formatted_lines[@scroll_offset, context.content_height] || []).length
            empty_line = "#{panel_bg}#{' ' * context.content_width}#{reset}"
            remaining = context.content_height - visible_count
            remaining.times do |index|
              row = context.content_y + visible_count + index
              context.surface.write(context.bounds, row, context.content_x, empty_line)
            end
          end


          def overlay_layout(bounds)
            sizing = @setup_mode ? @setup_overlay_sizing : @overlay_sizing
            width = sizing.width_for(bounds.width)
            height = overlay_height(bounds, sizing, width)
            Ui::OverlayLayout.centered(bounds, width: width, height: height)
          end

          def overlay_height(bounds, sizing, width)
            height = sizing.height_for(bounds.height)
            return height unless @setup_mode

            content_width = [width - (self.class::PADDING_H * 2), 12].max
            needed_height = build_setup_lines(content_width).length + (self.class::PADDING_V * 2) + 1
            max_height = [bounds.height - 4, 12].max
            height.clamp(needed_height, max_height)
          end

          def card_line(content, width:, active:)
            background = active ? active_card_bg : card_bg
            safe = apply_background_reset(content, background)
            padding = [width - visible_length(safe) - 2, 0].max
            "#{background} #{safe}#{' ' * padding} #{panel_bg}"
          end

          def style_text(text, color: nil, bold: false, dim: false, italic: false)
            prefix = +''
            prefix << color.to_s if color
            prefix << Shoko::Shared::Terminal::Ansi::BOLD if bold
            prefix << Shoko::Shared::Terminal::Ansi::DIM if dim
            prefix << Shoko::Shared::Terminal::Ansi::ITALIC if italic
            "#{prefix}#{text}#{text_reset}"
          end

          def text_reset
            "\e[39;22;23;24m"
          end

          def pad_line(text, width)
            safe = apply_background_reset(text, panel_bg)
            padding = [width - visible_length(safe), 0].max
            "#{panel_bg}#{safe}#{' ' * padding}#{reset}"
          end

          def apply_background_reset(text, background)
            text.to_s.gsub(reset, "#{text_reset}#{background}")
          end

          def visible_length(text)
            Shared::Terminal::TextMetrics.visible_length(text.to_s)
          rescue Shoko::Error
            text.to_s.gsub(/\e\[[0-9;]*m/, '').length
          end

          def panel_bg
            @color_mode == :light ? self.class::POPUP_BG_LIGHT : self.class::POPUP_BG
          end

          def card_bg
            @color_mode == :light ? self.class::CARD_BG_LIGHT : self.class::CARD_BG
          end

          def active_card_bg
            @color_mode == :light ? "\e[48;5;250m" : "\e[48;5;240m"
          end

          def reset
            Shoko::Shared::Terminal::Ansi::RESET
          end

          def max_scroll_offset
            content_height = @last_content_height || 10
            [@formatted_lines.length - content_height, 0].max
          end

        end
      end
    end
  end
end
