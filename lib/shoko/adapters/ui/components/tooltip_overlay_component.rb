# frozen_string_literal: true

require_relative 'base_component'
require_relative '../../../shared/terminal/text_metrics'
require_relative '../../../core/models/selection_anchor'
module Shoko
  module Adapters
    module Ui
      module Components
        # Unified overlay component that handles all tooltip/popup rendering
        # including text selection highlighting, popup menus, and annotations.
        #
        # This component consolidates the scattered rendering logic and provides
        # consistent coordinate handling for the fragile tooltip system.
        class TooltipOverlayComponent < BaseComponent
          include Adapters::Ui::Constants::Ui
          SEARCH_CONTEXT_WINDOW = 48

          def initialize(coordinate_service:, reader_state_reader:, rendered_content_reader:)
            super()
            @coordinate_service = coordinate_service
            @reader_state_reader = reader_state_reader
            @rendered_content_reader = rendered_content_reader
            @last_selection_segments = []
            @last_search_highlight_segments = []
            @geometry_cache_key = nil
            @geometry_cache = nil
          end

          # Render all overlay elements: highlights, popups, tooltips
          def do_render(surface, bounds)
            # Render in specific order to ensure proper layering
            clear_previous_selection_artifacts(surface, bounds)
            clear_previous_search_highlight_artifacts(surface, bounds)
            render_saved_annotations(surface, bounds)
            render_search_landing_highlight(surface, bounds)
            render_active_selection(surface, bounds)
            render_popup_menu(surface, bounds)
            render_annotations_overlay(surface, bounds)
            render_annotation_editor_overlay(surface, bounds)
            render_dictionary_popup(surface, bounds)
            render_in_book_search_popup(surface, bounds)
            render_toast_notification(surface, bounds)
          end

          private

          def render_saved_annotations(surface, bounds)
            anns = reader_state_reader&.annotations
            return unless anns

            current_ch = reader_state_reader&.current_chapter || 0
            chapter_annotations = anns.select { |annotation| annotation['chapter_index'] == current_ch }
            chapter_annotations.each do |annotation|
              render_text_highlight(surface, bounds, annotation['range'], HIGHLIGHT_BG_SAVED)
            end
          end

          def render_active_selection(surface, bounds)
            # Render current selection highlight
            selection_range = reader_state_reader&.selection

            unless selection_range
              # No active selection; keep any previously rendered segments for one clear pass
              @pending_clear = true if @last_selection_segments.any?
              return
            end

            # Reset tracking for this frame
            @last_selection_segments.clear
            @pending_clear = false
            render_text_highlight(surface, bounds, selection_range, HIGHLIGHT_BG_ACTIVE)
          end

          def render_search_landing_highlight(surface, bounds)
            highlight = reader_state_reader&.search_landing_highlight
            unless active_search_landing_highlight?(highlight)
              @pending_search_highlight_clear = true if @last_search_highlight_segments.any?
              return
            end

            @last_search_highlight_segments.clear
            @pending_search_highlight_clear = false
            render_search_geometry_highlight(surface, bounds, highlight)
          end

          def render_popup_menu(surface, bounds)
            popup_menu = reader_state_reader&.popup_menu
            return unless popup_menu&.visible

            # Unified component rendering path
            popup_menu.render(surface, bounds)
          end

          def render_annotations_overlay(surface, bounds)
            overlay = reader_state_reader&.annotations_overlay
            return unless overlay&.visible? == true

            overlay.render(surface, bounds)
          end

          def render_annotation_editor_overlay(surface, bounds)
            overlay = reader_state_reader&.annotation_editor_overlay
            return unless overlay&.visible? == true

            overlay.render(surface, bounds)
          end

          def render_dictionary_popup(surface, bounds)
            popup = reader_state_reader&.dictionary_popup
            return unless popup&.visible? == true

            popup.render(surface, bounds)
          end

          def render_in_book_search_popup(surface, bounds)
            popup = reader_state_reader&.in_book_search_popup
            return unless popup&.visible? == true

            popup.render(surface, bounds)
          end

          def render_toast_notification(surface, bounds)
            message = reader_state_reader&.message.to_s
            return if message.empty?

            ui = Adapters::Ui::Constants::Ui
            width = bounds.width
            max_width = [width - 2, 1].max
            label_max = [max_width - 1, 1].max
            label = " #{message} "
            label = Shoko::Shared::Terminal::TextMetrics.truncate_to(label, label_max)
            content = "|#{label}"
            col = [width - Shoko::Shared::Terminal::TextMetrics.visible_length(content) + 1, 1].max

            toast = "#{Shoko::Shared::Terminal::Ansi::RESET}#{ui::TOAST_ACCENT}|#{ui::TOAST_FG}#{label}#{Shoko::Shared::Terminal::Ansi::RESET}"
            surface.write(bounds, 1, col, toast)
          end

          def render_text_highlight(surface, bounds, range, color)
            rendered_lines = rendered_content_reader&.rendered_lines || {}
            return if rendered_lines.empty?

            normalized_range = @coordinate_service.normalize_selection_range(range, rendered_lines)
            return unless normalized_range

            start_anchor = Shoko::Core::Models::SelectionAnchor.from(normalized_range[:start])
            end_anchor = Shoko::Core::Models::SelectionAnchor.from(normalized_range[:end])
            return unless start_anchor && end_anchor

            cache = geometry_cache_for(rendered_lines)
            ordered = cache[:ordered]
            index_by_key = cache[:index_by_key]
            return if ordered.empty?

            start_idx = index_by_key[start_anchor.geometry_key]
            end_idx = index_by_key[end_anchor.geometry_key]
            return unless start_idx && end_idx

            ordered[start_idx..end_idx].each do |geometry|
              start_cell = geometry.key == start_anchor.geometry_key ? start_anchor.cell_index : 0
              end_cell = geometry.key == end_anchor.geometry_key ? end_anchor.cell_index : geometry.cells.length
              render_geometry_highlight(surface, bounds, geometry, start_cell, end_cell, color)
            end
          end

          def render_geometry_highlight(surface, bounds, geometry, start_cell, end_cell, color,
                                        foreground: COLOR_TEXT_PRIMARY, tracker: :selection)
            return if end_cell <= start_cell

            start_char = char_index_for_cell(geometry, start_cell)
            end_char = char_index_for_cell(geometry, end_cell)
            return if end_char <= start_char

            segment_text = geometry.plain_text[start_char...end_char]
            return if segment_text.nil? || segment_text.empty?

            highlight = "#{color}#{foreground}#{segment_text}#{Shoko::Shared::Terminal::Ansi::RESET}"
            start_col = screen_column_for_cell(geometry, start_cell)
            surface.write_abs(bounds, geometry.row, start_col, highlight)
            record_highlight_segment(tracker, geometry.row, start_col, segment_text)
          end

          def screen_column_for_cell(geometry, cell_index)
            if cell_index <= 0
              geometry.column_origin
            elsif cell_index >= geometry.cells.length
              geometry.column_origin + geometry.visible_width
            else
              geometry.column_origin + geometry.cells[cell_index].screen_x
            end
          end

          def char_index_for_cell(geometry, cell_index)
            cells = geometry.cells
            return 0 if cells.empty?

            if cell_index <= 0
              0
            elsif cell_index >= cells.length
              geometry.plain_text.length
            else
              cells[cell_index].char_start
            end
          end

          def geometry_cache_for(rendered_lines)
            cache_key = rendered_lines.object_id
            return @geometry_cache if @geometry_cache_key == cache_key && @geometry_cache

            geometry_by_key = {}
            rendered_lines.each do |key, info|
              geometry = info[:geometry]
              next unless geometry

              geometry_by_key[key] = geometry
            end
            ordered = order_geometry(geometry_by_key.values)
            index_by_key = {}
            ordered.each_with_index { |geo, idx| index_by_key[geo.key] = idx }

            @geometry_cache_key = cache_key
            @geometry_cache = { ordered: ordered, index_by_key: index_by_key }
          end

          def order_geometry(geometries)
            geometries.sort_by do |geo|
              [geo.page_id || 0, geo.line_offset || 0, geo.column_id || 0, geo.row || 0, geo.column_origin || 0]
            end
          end

          def record_highlight_segment(kind, row, col, text)
            collection = kind == :search_landing ? @last_search_highlight_segments : @last_selection_segments
            collection << {
              row: row,
              col: col,
              text: text,
            }
          end

          # If selection was present on previous frame but not this one, explicitly repaint
          # the previously highlighted character cells to clear any lingering background color
          def clear_previous_selection_artifacts(surface, bounds)
            return unless @pending_clear && @last_selection_segments.any?

            @last_selection_segments.each do |seg|
              safe_text = seg[:text] || ''
              reset = Shoko::Shared::Terminal::Ansi::RESET
              repaint = "#{reset}#{COLOR_TEXT_PRIMARY}#{safe_text}#{reset}"
              surface.write_abs(bounds, seg[:row], seg[:col], repaint)
            end

            @last_selection_segments.clear
            @pending_clear = false
          end

          def clear_previous_search_highlight_artifacts(surface, bounds)
            return unless @pending_search_highlight_clear && @last_search_highlight_segments.any?

            @last_search_highlight_segments.each do |seg|
              safe_text = seg[:text] || ''
              reset = Shoko::Shared::Terminal::Ansi::RESET
              repaint = "#{reset}#{COLOR_TEXT_PRIMARY}#{safe_text}#{reset}"
              surface.write_abs(bounds, seg[:row], seg[:col], repaint)
            end

            @last_search_highlight_segments.clear
            @pending_search_highlight_clear = false
          end

          def active_search_landing_highlight?(highlight)
            return false unless highlight.is_a?(Hash)

            chapter_index = highlight_value(highlight, :chapter_index)
            return false if chapter_index && chapter_index.to_i != reader_state_reader&.current_chapter.to_i
            return false if search_highlight_expired?(highlight)

            highlight_match_text(highlight).length.positive?
          end

          def render_search_geometry_highlight(surface, bounds, highlight)
            rendered_lines = rendered_content_reader&.rendered_lines || {}
            return if rendered_lines.empty?

            geometry_groups = search_highlight_geometry_groups(rendered_lines, highlight)
            return if geometry_groups.empty?

            match = locate_search_highlight_match(geometry_groups, highlight)
            return unless match

            match.each do |segment|
              render_search_geometry_segment(surface, bounds, segment[:geometry], segment[:start_char], segment[:end_char])
            end
          end

          def render_search_geometry_segment(surface, bounds, geometry, start_char, end_char)
            start_cell = cell_index_for_char(geometry, start_char)
            end_cell = cell_index_for_char(geometry, end_char, use_end_boundary: true)
            render_geometry_highlight(
              surface,
              bounds,
              geometry,
              start_cell,
              end_cell,
              SEARCH_HIGHLIGHT_BG,
              foreground: SEARCH_HIGHLIGHT_FG,
              tracker: :search_landing
            )
          end

          def search_highlight_geometry_groups(rendered_lines, highlight)
            ordered = geometry_cache_for(rendered_lines)[:ordered]
            target_line = integer_highlight_value(highlight, :line_index)
            groups = ordered.group_by(&:line_offset).values
            return groups if target_line.nil?

            exact = groups.select { |group| group.first&.line_offset.to_i == target_line }
            return exact unless exact.empty?

            groups
          end

          def locate_search_highlight_match(geometry_groups, highlight)
            geometry_groups.each_with_object([]) do |group, matches|
              match = locate_search_highlight_match_in_group(group, highlight)
              matches << match if match
            end.max_by { |match| [match[:score], -match[:start]] }&.fetch(:segments, nil)
          end

          def locate_search_highlight_match_in_group(geometries, highlight)
            full_text = geometries.map(&:plain_text).join
            needle = highlight_match_text(highlight)
            return nil if full_text.empty? || needle.empty?

            candidates = case_insensitive_occurrences(full_text, needle)
            candidates = case_insensitive_occurrences(full_text, highlight_query_text(highlight)) if candidates.empty?
            return nil if candidates.empty?

            scored_candidates = candidates.map do |candidate|
              {
                candidate: candidate,
                score: search_context_score(full_text, candidate, highlight),
              }
            end
            return nil if ambiguous_search_highlight_match?(scored_candidates)

            best = scored_candidates.max_by { |entry| [entry[:score], -entry[:candidate][:start]] }
            {
              score: best[:score],
              start: best[:candidate][:start],
              segments: search_highlight_segments_for(geometries, best[:candidate][:start], best[:candidate][:end]),
            }
          end

          def ambiguous_search_highlight_match?(scored_candidates)
            scored_candidates.length > 1 && scored_candidates.all? { |entry| entry[:score].zero? }
          end

          def case_insensitive_occurrences(text, needle)
            return [] if needle.to_s.empty?

            pattern = Regexp.new(Regexp.escape(needle.to_s), Regexp::IGNORECASE)
            matches = []
            offset = 0
            while (match = pattern.match(text, offset))
              matches << { start: match.begin(0), end: match.end(0) }
              offset = match.begin(0) + [match[0].length, 1].max
            end
            matches
          end

          def search_context_score(text, candidate, highlight)
            before = highlight_before_text(highlight)
            after = highlight_after_text(highlight)
            score = 0
            score += 4 if !before.empty? && text[[candidate[:start] - before.length, 0].max...candidate[:start]].to_s.casecmp(before).zero?
            score += 4 if !after.empty? && text[candidate[:end], after.length].to_s.casecmp(after).zero?

            window_start = [candidate[:start] - SEARCH_CONTEXT_WINDOW, 0].max
            window_end = [candidate[:end] + SEARCH_CONTEXT_WINDOW, text.length].min
            window = text[window_start...window_end].to_s.downcase
            score += 1 if !before.empty? && window.include?(before.downcase)
            score += 1 if !after.empty? && window.include?(after.downcase)
            score
          end

          def search_highlight_segments_for(geometries, start_char, end_char)
            cursor = 0
            geometries.each_with_object([]) do |geometry, segments|
              geometry_end = cursor + geometry.plain_text.length
              overlap_start = [start_char, cursor].max
              overlap_end = [end_char, geometry_end].min
              if overlap_end > overlap_start
                segments << {
                  geometry: geometry,
                  start_char: overlap_start - cursor,
                  end_char: overlap_end - cursor,
                }
              end
              cursor = geometry_end
            end
          end

          def cell_index_for_char(geometry, char_index, use_end_boundary: false)
            cells = geometry.cells
            return 0 if char_index.to_i <= 0
            return cells.length if cells.empty?

            if use_end_boundary
              cells.index { |cell| cell.char_start >= char_index } || cells.length
            else
              cells.index { |cell| cell.char_end > char_index } || cells.length
            end
          end

          def highlight_value(highlight, key)
            highlight[key] || highlight[key.to_s]
          end

          def integer_highlight_value(highlight, key)
            Integer(highlight_value(highlight, key))
          rescue ArgumentError, TypeError
            nil
          end

          def float_highlight_value(highlight, key)
            Float(highlight_value(highlight, key))
          rescue ArgumentError, TypeError
            nil
          end

          def highlight_match_text(highlight)
            highlight_value(highlight, :match_text).to_s
          end

          def highlight_query_text(highlight)
            highlight_value(highlight, :query).to_s
          end

          def highlight_before_text(highlight)
            highlight_value(highlight, :before).to_s
          end

          def highlight_after_text(highlight)
            highlight_value(highlight, :after).to_s
          end

          def search_highlight_expired?(highlight)
            expires_at = float_highlight_value(highlight, :expires_at)
            expires_at && monotonic_now >= expires_at
          end

          def monotonic_now
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end

          def reader_state_reader
            @reader_state_reader
          end

          def rendered_content_reader
            @rendered_content_reader
          end

          # Column bounds and overlap checks are now handled by CoordinateService
        end
      end
    end
  end
end
