# frozen_string_literal: true

require_relative '../base_component'

module Shoko
  module Adapters
    module Ui
      module Components
        class TooltipOverlayComponent < BaseComponent
          # Search-result landing highlight selection and context scoring.
          module SearchHighlightSupport
            UI = Adapters::Ui::Constants::Ui

            private

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
end
