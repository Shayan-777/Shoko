# frozen_string_literal: true

require 'shoko/shared/hash_normalizer'
require 'shoko/shared/type_coercion'

module Shoko
  module Adapters
    module Storage
      class SqliteDictionaryAdapter
        # Stateless ranking and similarity scoring for fuzzy dictionary search.
        #
        # A pure collaborator: every method operates on its arguments only (no
        # instance state), so it is exposed as module functions and called as
        # `FuzzyRanker.score_candidates(...)` / `FuzzyRanker.filter_and_sort_fuzzy(...)`
        # from the query path. Extracted from the former `FuzzyRankingSupport` /
        # `LevenshteinSupport` mixins (audit ARCH-3).
        module FuzzyRanker
          module_function

          def score_candidates(word, candidates, similarity_threshold:)
            normalized_word = normalize_for_comparison(word)
            word_lower = word.downcase

            candidates.filter_map do |row|
              build_scored_candidate(
                word: word,
                word_lower: word_lower,
                normalized_word: normalized_word,
                row: row,
                similarity_threshold: similarity_threshold
              )
            end
          end

          def filter_and_sort_fuzzy(scored, limit, similarity_threshold:)
            scored
              .select { |row| row[:similarity] > similarity_threshold }
              .sort_by do |row|
                [-row[:similarity], -row[:importance], -row[:score], row[:word].length,
                 row[:word].downcase]
              end
              .take(limit)
          end

          def calculate_similarity(word_lower, normalized_word, candidate, similarity_threshold:)
            candidate_lower = candidate.downcase
            candidate_normalized = normalize_for_comparison(candidate)
            max_len = [word_lower.length, candidate.length].max
            return nil if max_len.zero?

            max_distance = ((1.0 - similarity_threshold) * max_len).floor

            distance_raw = levenshtein_distance(word_lower, candidate_lower, max_distance: max_distance)
            distance_normalized = levenshtein_distance(normalized_word,
                                                       candidate_normalized,
                                                       max_distance: max_distance)
            best_distance = [distance_raw, distance_normalized].min
            return nil if best_distance > max_distance

            1.0 - (best_distance.to_f / max_len)
          end

          def normalize_for_comparison(word)
            word.unicode_normalize(:nfkd).downcase.gsub(/\p{Mn}+/, '').gsub('ß', 'ss')
          end

          def composite_similarity(word:, candidate:, normalized_word:, candidate_normalized:, edit_similarity:,
                                   importance:, score:)
            base = weighted_similarity_components(
              normalized_word: normalized_word,
              candidate_normalized: candidate_normalized,
              edit_similarity: edit_similarity
            )
            bonuses = similarity_bonus(
              word: word,
              candidate: candidate,
              normalized_word: normalized_word,
              candidate_normalized: candidate_normalized,
              importance: importance,
              score: score
            )

            (base + bonuses).clamp(0.0, 0.999)
          end

          def ngram_similarity(source, target, size)
            source_grams = grams_for(source, size)
            target_grams = grams_for(target, size)
            return 0.0 if source_grams.empty? || target_grams.empty?

            overlap = source_grams.sum do |gram, count|
              [count, target_grams.fetch(gram, 0)].min
            end
            denominator = source_grams.values.sum + target_grams.values.sum
            return 0.0 if denominator.zero?

            (2.0 * overlap) / denominator
          end

          def grams_for(value, size)
            text = value.to_s
            return {} if text.length < size

            counts = Hash.new(0)
            0.upto(text.length - size) do |index|
              counts[text[index, size]] += 1
            end
            counts
          end

          def shared_edge_ratio(source, target, edge)
            limit = [source.length, target.length].min
            return 0.0 if limit.zero?

            shared = 0
            while shared < limit
              source_index = edge == :suffix ? -1 - shared : shared
              target_index = edge == :suffix ? -1 - shared : shared
              break unless source[source_index] == target[target_index]

              shared += 1
            end

            shared.to_f / [source.length, target.length].max
          end

          def case_similarity_adjustment(word, candidate)
            return 0.0 if word.to_s.empty? || candidate.to_s.empty?

            query = word.to_s
            token = candidate.to_s
            return -0.08 if query == query.downcase && token[0] == token[0].upcase
            return 0.02 if query[0] == query[0].upcase && token[0] == token[0].upcase

            0.0
          end

          def numeric_rank_value(value)
            Shoko::Shared::TypeCoercion.optional_float(value) || 0.0
          end

          def normalize_candidate_row(row)
            Shoko::Shared::HashNormalizer.symbolize_keys(row) || {}
          end

          def build_scored_candidate(word:, word_lower:, normalized_word:, row:, similarity_threshold:)
            normalized = normalize_candidate_row(row)
            candidate = normalized[:written_rep]
            return nil if candidate.to_s.empty?

            importance, score = candidate_rank_values(normalized)
            similarity = candidate_similarity(word:,
                                              word_lower:,
                                              normalized_word:,
                                              candidate:,
                                              similarity_threshold:,
                                              importance:,
                                              score:)
            return nil unless similarity

            scored_candidate(candidate, similarity, importance, score)
          end

          def weighted_similarity_components(normalized_word:, candidate_normalized:, edit_similarity:)
            [
              [edit_similarity, 0.60],
              [ngram_similarity(normalized_word, candidate_normalized, 2), 0.16],
              [ngram_similarity(normalized_word, candidate_normalized, 3), 0.10],
              [shared_edge_ratio(normalized_word, candidate_normalized, :prefix), 0.06],
              [shared_edge_ratio(normalized_word, candidate_normalized, :suffix), 0.05],
            ].sum { |value, weight| value * weight }
          end

          def similarity_bonus(word:, candidate:, normalized_word:, candidate_normalized:, importance:, score:)
            importance_bonus = [importance, 1.0].min * 0.08
            score_bonus = (score / 250.0).clamp(0.0, 1.0) * 0.02
            start_bonus = normalized_word[0] == candidate_normalized[0] ? 0.03 : 0.0

            importance_bonus + score_bonus + start_bonus + case_similarity_adjustment(word, candidate)
          end

          def candidate_rank_values(normalized)
            importance = numeric_rank_value(normalized[:rel_importance] || normalized[:importance])
            score = numeric_rank_value(normalized[:max_score] || normalized[:score])
            [importance, score]
          end

          def candidate_similarity(word:, word_lower:, normalized_word:, candidate:, similarity_threshold:, importance:,
                                   score:)
            candidate_normalized = normalize_for_comparison(candidate)
            edit_similarity = calculate_similarity(word_lower,
                                                   normalized_word,
                                                   candidate,
                                                   similarity_threshold: similarity_threshold)
            return nil unless edit_similarity

            composite_similarity(
              word: word,
              candidate: candidate,
              normalized_word: normalized_word,
              candidate_normalized: candidate_normalized,
              edit_similarity: edit_similarity,
              importance: importance,
              score: score
            )
          end

          def scored_candidate(candidate, similarity, importance, score)
            { word: candidate, similarity: similarity, importance: importance, score: score }
          end

          # ── Bounded Levenshtein (formerly LevenshteinSupport) ──────────────

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
            [previous[target_index] + 1, current[target_index - 1] + 1, previous[target_index - 1] + cost].min
          end
        end
      end
    end
  end
end
