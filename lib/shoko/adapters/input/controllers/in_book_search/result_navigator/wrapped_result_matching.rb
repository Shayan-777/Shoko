# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        class InBookSearchController
          class ResultNavigator
            # Scores wrapped-result snippet candidates against the flattened page text.
            module WrappedResultMatching
              private

              def locate_wrapped_line_offset(chapter_index_data, result_entry)
                search_text = chapter_index_data[:text]
                spans = chapter_index_data[:spans]
                context = wrapped_search_context(result_entry)
                return nil unless searchable_wrapped_context?(search_text, context)

                match = locate_wrapped_search_match(search_text, wrapped_search_targets(context), context)
                return nil unless match

                line_offset_for_char_index(spans, match[:match_start])
              end

              def wrapped_search_context(result_entry)
                {
                  before_text: normalize_search_text(result_value(result_entry, :before)),
                  match_text: normalize_search_text(result_value(result_entry, :match)),
                  after_text: normalize_search_text(result_value(result_entry, :after)),
                  query_text: normalize_search_text(result_value(result_entry, :query)),
                }
              end

              def searchable_wrapped_context?(search_text, context)
                !search_text.to_s.empty? && !context[:match_text].empty?
              end

              def wrapped_search_targets(context)
                targets = []
                wrapped_search_target_definitions(context).each do |definition|
                  append_wrapped_search_target(targets, **definition)
                end
                targets
              end

              def wrapped_search_target_definitions(context)
                targets = base_wrapped_search_targets(context)
                append_wrapped_context_targets(targets, context)
                append_wrapped_query_target(targets, context)
                targets
              end

              def base_wrapped_search_targets(context)
                [
                  {
                    text: "#{context[:before_text]}#{context[:match_text]}#{context[:after_text]}",
                    match_offset: context[:before_text].length,
                    base: 40,
                  },
                  {
                    text: context[:match_text],
                    match_offset: 0,
                    base: 20,
                  },
                ]
              end

              def append_wrapped_context_targets(targets, context)
                append_wrapped_context_target(targets, context[:before_text], context[:match_text], 32)
                append_wrapped_context_target(targets, context[:after_text], context[:match_text], 32, trailing: true)
              end

              def append_wrapped_context_target(targets, context_text, match_text, base, trailing: false)
                return if context_text.empty?

                text = trailing ? "#{match_text}#{context_text}" : "#{context_text}#{match_text}"
                match_offset = trailing ? 0 : context_text.length
                targets << { text: text, match_offset: match_offset, base: base }
              end

              def append_wrapped_query_target(targets, context)
                query_text = context[:query_text]
                return if query_text.empty? || query_text == context[:match_text]

                targets << { text: query_text, match_offset: 0, base: 16 }
              end

              def append_wrapped_search_target(targets, text:, match_offset:, base:)
                return if text.empty?

                key = [text, match_offset]
                return if targets.any? { |candidate| key == [candidate[:text], candidate[:match_offset]] }

                targets << { text: text, match_offset: match_offset, base: base }
              end

              def locate_wrapped_search_match(text, targets, context)
                wrapped_search_matches(text, targets, context)
                  .max_by { |match| [match[:score], -match[:match_start]] }
              end

              def wrapped_search_matches(text, targets, context)
                Array(targets).flat_map do |target|
                  wrapped_search_occurrences(text, target[:text]).map do |occurrence|
                    build_wrapped_search_match(text, occurrence, target, context)
                  end
                end
              end

              def build_wrapped_search_match(text, occurrence, target, context)
                match_start = occurrence[:start] + target[:match_offset]
                {
                  score: wrapped_search_match_score(text, match_start, context, target[:base]),
                  match_start: match_start,
                }
              end

              def wrapped_search_occurrences(text, needle)
                return [] if text.to_s.empty? || needle.to_s.empty?

                matches = []
                offset = 0
                while (index = text.index(needle, offset))
                  matches << { start: index, finish: index + needle.length }
                  offset = index + [needle.length, 1].max
                end
                matches
              end

              def wrapped_search_match_score(text, match_start, context, base_score)
                match_end = match_start + context[:match_text].length
                base_score.to_i +
                  wrapped_search_exact_context_score(text, match_start, match_end, context) +
                  wrapped_search_window_score(text, match_start, match_end, context)
              end

              def wrapped_search_exact_context_score(text, match_start, match_end, context)
                score = 0
                score += 8 if wrapped_search_prefix_match?(text, match_start, context[:before_text])
                score += 8 if wrapped_search_suffix_match?(text, match_end, context[:after_text])
                score
              end

              def wrapped_search_window_score(text, match_start, match_end, context)
                window = wrapped_search_window(text, match_start, match_end)
                score = 0
                score += 2 if wrapped_search_window_include?(window, context[:before_text])
                score += 2 if wrapped_search_window_include?(window, context[:after_text])
                score
              end

              def wrapped_search_prefix_match?(text, match_start, before_text)
                return false if before_text.empty?

                text[[match_start - before_text.length, 0].max...match_start].to_s == before_text
              end

              def wrapped_search_suffix_match?(text, match_end, after_text)
                return false if after_text.empty?

                text[match_end, after_text.length].to_s == after_text
              end

              def wrapped_search_window(text, match_start, match_end)
                window_start = [match_start - SEARCH_CONTEXT_WINDOW, 0].max
                window_end = [match_end + SEARCH_CONTEXT_WINDOW, text.length].min
                text[window_start...window_end].to_s
              end

              def wrapped_search_window_include?(window, candidate)
                !candidate.empty? && window.include?(candidate)
              end

              def wrapped_search_result?(result_entry)
                result_value(result_entry, :line_space).casecmp('wrapped').zero?
              end
            end
          end
        end
      end
    end
  end
end
