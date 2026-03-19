# frozen_string_literal: true

require_relative '../../../shared/hash_normalizer'
require_relative 'fuzzy_ranking_support/levenshtein_support'

module Shoko
  module Adapters
    module Storage
      class SqliteDictionaryAdapter
        # Ranking and similarity helpers for fuzzy dictionary search.
        module FuzzyRankingSupport
          include LevenshteinSupport

          private

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

          def calculate_similarity(word_lower, normalized_word, candidate, similarity_threshold:)
            candidate_lower = candidate.downcase
            candidate_normalized = normalize_for_comparison(candidate)
            max_len = [word_lower.length, candidate.length].max
            return nil if max_len.zero?

            max_distance = ((1.0 - similarity_threshold) * max_len).floor

            distance_raw = levenshtein_distance(word_lower, candidate_lower, max_distance: max_distance)
            distance_normalized = levenshtein_distance(normalized_word, candidate_normalized,
                                                       max_distance: max_distance)
            best_distance = [distance_raw, distance_normalized].min
            return nil if best_distance > max_distance

            1.0 - (best_distance.to_f / max_len)
          end

          def normalize_for_comparison(word)
            word.unicode_normalize(:nfkd)
                .downcase
                .gsub(/\p{Mn}+/, '')
                .gsub('ß', 'ss')
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
            similarity = candidate_similarity(word:, word_lower:, normalized_word:, candidate:, similarity_threshold:,
                                              importance:, score:)
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
            edit_similarity = calculate_similarity(word_lower, normalized_word, candidate,
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
        end
      end
    end
  end
end
