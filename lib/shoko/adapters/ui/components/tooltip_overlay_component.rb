# frozen_string_literal: true

require_relative '../../../shared/type_coercion'

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

          UI = Adapters::Ui::Constants::Ui
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
            render_translation_popup(surface, bounds)
            render_in_book_search_popup(surface, bounds)
            render_toast_notification(surface, bounds)
          end

          private

          attr_reader :reader_state_reader, :rendered_content_reader

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

          def render_translation_popup(surface, bounds)
            state_reader = reader_state_reader
            return unless state_reader
            return unless state_reader.respond_to?(:translation_popup)

            popup = state_reader.translation_popup
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

          def monotonic_now
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end

          # Column bounds and overlap checks are now handled by CoordinateService

          # Geometry-to-screen highlight rendering for selections and search hits.
          def render_text_highlight(surface, bounds, range, color)
            rendered_lines = rendered_content_reader&.rendered_lines || {}
            return if rendered_lines.empty?

            anchors = normalized_highlight_anchors(range, rendered_lines)
            return unless anchors

            render_geometry_range(surface: surface,
                                  bounds: bounds,
                                  rendered_lines: rendered_lines,
                                  color: color,
                                  **anchors)
          end

          def normalized_highlight_anchors(range, rendered_lines)
            normalized_range = @coordinate_service.normalize_selection_range(range, rendered_lines)
            return nil unless normalized_range

            start_anchor = Shoko::Core::Models::SelectionAnchor.from(normalized_range[:start])
            end_anchor = Shoko::Core::Models::SelectionAnchor.from(normalized_range[:end])
            return nil unless start_anchor && end_anchor

            { start_anchor: start_anchor, end_anchor: end_anchor }
          end

          def render_geometry_range(surface:, bounds:, rendered_lines:, color:, start_anchor:, end_anchor:)
            cache = geometry_cache_for(rendered_lines)
            geometries = highlight_geometries(cache, start_anchor, end_anchor)
            return unless geometries

            geometries.each do |geometry|
              render_geometry_highlight(
                surface: surface,
                bounds: bounds,
                geometry: geometry,
                start_cell: highlight_start_cell(geometry, start_anchor),
                end_cell: highlight_end_cell(geometry, end_anchor),
                color: color
              )
            end
          end

          def highlight_geometries(cache, start_anchor, end_anchor)
            ordered = cache[:ordered]
            return nil if ordered.empty?

            start_idx = cache[:index_by_key][start_anchor.geometry_key]
            end_idx = cache[:index_by_key][end_anchor.geometry_key]
            return nil unless start_idx && end_idx

            ordered[start_idx..end_idx]
          end

          def highlight_start_cell(geometry, start_anchor)
            geometry.key == start_anchor.geometry_key ? start_anchor.cell_index : 0
          end

          def highlight_end_cell(geometry, end_anchor)
            geometry.key == end_anchor.geometry_key ? end_anchor.cell_index : geometry.cells.length
          end

          def render_geometry_highlight(surface:, bounds:, geometry:, start_cell:, end_cell:, color:,
                                        foreground: UI::COLOR_TEXT_PRIMARY, tracker: :selection)
            return if end_cell <= start_cell

            start_char = char_index_for_cell(geometry, start_cell)
            end_char = char_index_for_cell(geometry, end_cell)
            segment_text = highlighted_text_segment(geometry, start_char, end_char)
            return if segment_text.empty?

            highlight = "#{color}#{foreground}#{segment_text}#{Shoko::Shared::Terminal::Ansi::RESET}"
            start_col = screen_column_for_cell(geometry, start_cell)
            surface.write_abs(bounds, geometry.row, start_col, highlight)
            record_highlight_segment(tracker, geometry.row, start_col, segment_text)
          end

          def highlighted_text_segment(geometry, start_char, end_char)
            return '' if end_char <= start_char

            geometry.plain_text[start_char...end_char].to_s
          end

          def screen_column_for_cell(geometry, cell_index)
            return geometry.column_origin if cell_index <= 0
            return geometry.column_origin + geometry.visible_width if cell_index >= geometry.cells.length

            geometry.column_origin + geometry.cells[cell_index].screen_x
          end

          def char_index_for_cell(geometry, cell_index)
            cells = geometry.cells
            return 0 if cells.empty?
            return 0 if cell_index <= 0
            return geometry.plain_text.length if cell_index >= cells.length

            cells[cell_index].char_start
          end

          def cell_index_for_char(geometry, char_index, use_end_boundary: false)
            cells = geometry.cells
            return 0 if char_index.to_i <= 0
            return cells.length if cells.empty?

            match_cell_index(cells, char_index, use_end_boundary) || cells.length
          end

          def match_cell_index(cells, char_index, use_end_boundary)
            if use_end_boundary
              cells.index { |cell| cell.char_start >= char_index }
            else
              cells.index { |cell| cell.char_end > char_index }
            end
          end

          def geometry_cache_for(rendered_lines)
            cache_key = rendered_lines.object_id
            return @geometry_cache if @geometry_cache_key == cache_key && @geometry_cache

            @geometry_cache_key = cache_key
            @geometry_cache = build_geometry_cache(rendered_lines)
          end

          def build_geometry_cache(rendered_lines)
            ordered = order_geometry(geometry_entries_for(rendered_lines))
            {
              ordered: ordered,
              index_by_key: ordered.each_with_index.to_h { |geometry, index| [geometry.key, index] },
            }
          end

          def geometry_entries_for(rendered_lines)
            rendered_lines.each_with_object([]) do |(_key, info), geometries|
              geometry = info[:geometry]
              geometries << geometry if geometry
            end
          end

          def order_geometry(geometries)
            geometries.sort_by do |geometry|
              [
                geometry.page_id || 0,
                geometry.line_offset || 0,
                geometry.column_id || 0,
                geometry.row || 0,
                geometry.column_origin || 0,
              ]
            end
          end

          def record_highlight_segment(kind, row, col, text)
            highlight_segments(kind) << { row: row, col: col, text: text }
          end

          def highlight_segments(kind)
            kind == :search_landing ? @last_search_highlight_segments : @last_selection_segments
          end

          # If selection was present on previous frame but not this one, explicitly repaint
          # the previously highlighted character cells to clear any lingering background color
          def clear_previous_selection_artifacts(surface, bounds)
            return unless @pending_clear && @last_selection_segments.any?

            clear_recorded_highlight_segments(surface, bounds, @last_selection_segments)
            @pending_clear = false
          end

          def clear_previous_search_highlight_artifacts(surface, bounds)
            return unless @pending_search_highlight_clear && @last_search_highlight_segments.any?

            clear_recorded_highlight_segments(surface, bounds, @last_search_highlight_segments)
            @pending_search_highlight_clear = false
          end

          def clear_recorded_highlight_segments(surface, bounds, segments)
            reset = Shoko::Shared::Terminal::Ansi::RESET
            segments.each do |segment|
              repaint = "#{reset}#{UI::COLOR_TEXT_PRIMARY}#{segment[:text]}#{reset}"
              surface.write_abs(bounds, segment[:row], segment[:col], repaint)
            end
            segments.clear
          end

          # Search-result landing highlight selection and context scoring.
          def render_search_landing_highlight(surface, bounds)
            highlight = normalize_search_highlight(reader_state_reader&.search_landing_highlight)
            unless active_search_landing_highlight?(highlight)
              @pending_search_highlight_clear = true if @last_search_highlight_segments.any?
              return
            end

            @last_search_highlight_segments.clear
            @pending_search_highlight_clear = false
            render_search_geometry_highlight(surface, bounds, highlight)
          end

          def active_search_landing_highlight?(highlight)
            highlight &&
              highlight_matches_current_chapter?(highlight) &&
              !search_highlight_expired?(highlight) &&
              highlight[:match_text].length.positive?
          end

          def highlight_matches_current_chapter?(highlight)
            chapter_index = highlight[:chapter_index]
            return true if chapter_index.nil?

            chapter_index.to_i == reader_state_reader&.current_chapter.to_i
          end

          def render_search_geometry_highlight(surface, bounds, highlight)
            rendered_lines = rendered_content_reader&.rendered_lines || {}
            return if rendered_lines.empty?

            match = locate_search_highlight_match(search_highlight_geometry_groups(rendered_lines, highlight),
                                                  highlight)
            return unless match

            match.each do |segment|
              render_search_geometry_segment(surface, bounds, segment)
            end
          end

          def render_search_geometry_segment(surface, bounds, segment)
            geometry = segment[:geometry]
            render_geometry_highlight(
              surface: surface,
              bounds: bounds,
              geometry: geometry,
              start_cell: cell_index_for_char(geometry, segment[:start_char]),
              end_cell: cell_index_for_char(geometry, segment[:end_char], use_end_boundary: true),
              color: UI::SEARCH_HIGHLIGHT_BG,
              foreground: UI::SEARCH_HIGHLIGHT_FG,
              tracker: :search_landing
            )
          end

          def search_highlight_geometry_groups(rendered_lines, highlight)
            groups = geometry_cache_for(rendered_lines)[:ordered].group_by(&:line_offset).values
            target_line = Shoko::Shared::TypeCoercion.optional_integer(highlight[:line_index])
            return groups if target_line.nil?

            exact_groups = groups.select { |group| group.first&.line_offset.to_i == target_line }
            exact_groups.empty? ? groups : exact_groups
          end

          def locate_search_highlight_match(geometry_groups, highlight)
            matches = geometry_groups.filter_map do |group|
              locate_search_highlight_match_in_group(group, highlight)
            end
            best_match = matches.max_by { |match| [match[:score], -match[:start]] }
            best_match && best_match[:segments]
          end

          def locate_search_highlight_match_in_group(geometries, highlight)
            full_text = geometries.map(&:plain_text).join
            candidates = search_candidates_for(full_text, highlight)
            return nil if candidates.empty?

            scored_candidates = score_search_candidates(full_text, candidates, highlight)
            return nil if ambiguous_search_highlight_match?(scored_candidates)

            build_search_highlight_match(geometries, best_search_candidate(scored_candidates))
          end

          def search_candidates_for(full_text, highlight)
            return [] if full_text.empty?

            match_text = highlight[:match_text].to_s
            return [] if match_text.empty?

            candidates = case_insensitive_occurrences(full_text, match_text)
            return candidates unless candidates.empty?

            case_insensitive_occurrences(full_text, highlight[:query].to_s)
          end

          def score_search_candidates(full_text, candidates, highlight)
            candidates.map do |candidate|
              {
                candidate: candidate,
                score: search_context_score(full_text, candidate, highlight),
              }
            end
          end

          def ambiguous_search_highlight_match?(scored_candidates)
            scored_candidates.length > 1 && scored_candidates.all? { |entry| entry[:score].zero? }
          end

          def best_search_candidate(scored_candidates)
            scored_candidates.max_by { |entry| [entry[:score], -entry[:candidate][:start]] }
          end

          def build_search_highlight_match(geometries, scored_candidate)
            return nil unless scored_candidate

            candidate = scored_candidate[:candidate]
            {
              score: scored_candidate[:score],
              start: candidate[:start],
              segments: search_highlight_segments_for(geometries, candidate[:start], candidate[:end]),
            }
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
            before = highlight[:before].to_s
            after = highlight[:after].to_s
            direct_context_score(text, candidate, before, after) +
              nearby_context_score(text, candidate, before, after)
          end

          def direct_context_score(text, candidate, before, after)
            score = 0
            score += 4 if before_context_match?(text, candidate, before)
            score += 4 if after_context_match?(text, candidate, after)
            score
          end

          def nearby_context_score(text, candidate, before, after)
            window = search_context_window(text, candidate)
            score = 0
            score += 1 if context_window_contains?(window, before)
            score += 1 if context_window_contains?(window, after)
            score
          end

          def before_context_match?(text, candidate, before)
            return false if before.empty?

            before_start = [candidate[:start] - before.length, 0].max
            text[before_start...candidate[:start]].to_s.casecmp(before).zero?
          end

          def after_context_match?(text, candidate, after)
            return false if after.empty?

            text[candidate[:end], after.length].to_s.casecmp(after).zero?
          end

          def search_context_window(text, candidate)
            window_start = [candidate[:start] - SEARCH_CONTEXT_WINDOW, 0].max
            window_end = [candidate[:end] + SEARCH_CONTEXT_WINDOW, text.length].min
            text[window_start...window_end].to_s.downcase
          end

          def context_window_contains?(window, excerpt)
            !excerpt.empty? && window.include?(excerpt.downcase)
          end

          def search_highlight_segments_for(geometries, start_char, end_char)
            cursor = 0
            geometries.each_with_object([]) do |geometry, segments|
              segment = search_highlight_segment_for_geometry(geometry, cursor, start_char, end_char)
              segments << segment if segment
              cursor += geometry.plain_text.length
            end
          end

          def search_highlight_segment_for_geometry(geometry, cursor, start_char, end_char)
            overlap = search_highlight_overlap_range(cursor, geometry.plain_text.length, start_char, end_char)
            return nil unless overlap

            {
              geometry: geometry,
              start_char: overlap[:start] - cursor,
              end_char: overlap[:end] - cursor,
            }
          end

          def search_highlight_overlap_range(cursor, text_length, start_char, end_char)
            geometry_end = cursor + text_length
            overlap_start = [start_char, cursor].max
            overlap_end = [end_char, geometry_end].min
            return nil unless overlap_end > overlap_start

            { start: overlap_start, end: overlap_end }
          end

          def normalize_search_highlight(highlight)
            return nil unless highlight.is_a?(Hash)

            highlight.transform_keys do |key|
              key.is_a?(String) ? key.to_sym : key
            end
          end

          def search_highlight_expired?(highlight)
            expires_at = Shoko::Shared::TypeCoercion.optional_float(highlight[:expires_at])
            expires_at && monotonic_now >= expires_at
          end
        end
      end
    end
  end
end
