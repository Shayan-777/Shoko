# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      class SqliteDictionaryAdapter
        module FuzzyRankingSupport
          # Provides the bounded Levenshtein implementation used for fuzzy ranking.
          module LevenshteinSupport
            private

            def levenshtein_distance(source, target, max_distance: nil)
              return target.length if source.empty?
              return source.length if target.empty?

              source_len = source.length
              target_len = target.length
              bounded = bounded_length_gap_distance(source_len, target_len, max_distance)
              return bounded if bounded

              compute_levenshtein_distance(
                source,
                target,
                source_len: source_len,
                target_len: target_len,
                max_distance: max_distance
              )
            end

            def bounded_length_gap_distance(source_len, target_len, max_distance)
              return nil unless max_distance
              return max_distance + 1 if (source_len - target_len).abs > max_distance

              nil
            end

            def compute_levenshtein_distance(source, target, source_len:, target_len:, max_distance:)
              previous = (0..target_len).to_a
              current = Array.new(target_len + 1, 0)
              row_state = { target_len: target_len, previous: previous, current: current }

              (1..source_len).each do |index|
                min_in_row = fill_distance_row!(source, target, index, row_state)
                return max_distance + 1 if max_distance && min_in_row > max_distance

                row_state[:previous], row_state[:current] = row_state[:current], row_state[:previous]
              end

              row_state[:previous][target_len]
            end

            def fill_distance_row!(source, target, source_index, row_state)
              current = row_state[:current]
              current[0] = source_index
              source_char = source[source_index - 1]
              1.upto(row_state[:target_len]) do |target_index|
                current[target_index] = distance_row_value(source_char, target, target_index, row_state)
              end

              current.min
            end

            def distance_row_value(source_char, target, target_index, row_state)
              previous = row_state[:previous]
              current = row_state[:current]
              cost = source_char == target[target_index - 1] ? 0 : 1
              [
                previous[target_index] + 1,
                current[target_index - 1] + 1,
                previous[target_index - 1] + cost,
              ].min
            end
          end
        end
      end
    end
  end
end
