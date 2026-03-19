# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        class AnnotationOverlayController
          class SpellcheckCoordinator
            # Chooses the spellcheck scope to show and ranks the returned candidates.
            module LookupResolution
              private

              def resolve_spell_lookup(word, target, scopes)
                state = normalize_spell_payload(session_payload(@ui_session&.editor_spell_suggestions_state))
                target = normalize_spell_payload(target)
                return best_spell_lookup(word, scopes) unless same_spell_target?(state, target)

                scope = next_spell_scope(scopes, state[:scope_key])
                {
                  scope: scope,
                  suggestions: spell_suggestions_for_scope(word, scope),
                }
              end

              def best_spell_lookup(word, scopes)
                selected = select_spell_scope_result(build_spell_scope_results(word, scopes), scopes.first)

                {
                  scope: selected[:scope],
                  suggestions: selected[:suggestions],
                }
              end

              def spell_ranked_matches_for_scope(word, scope)
                return [] unless scope.is_a?(Hash)

                sort_spell_matches(spell_match_candidates(word, scope))
              end

              def spell_suggestions_from_matches(matches)
                Array(matches).each_with_object([]) do |match, suggestions|
                  next if suggestions.any? { |existing| existing.casecmp(match[:word]).zero? }

                  suggestions << match[:word]
                  break suggestions if suggestions.length >= SPELL_SUGGESTION_LIMIT
                end
              end

              def same_spell_target?(state, target)
                return false unless state.is_a?(Hash) && target.is_a?(Hash)

                state_word = state[:word].to_s.strip
                target_word = target[:word].to_s.strip
                state_start = integer_value(state[:start])
                state_end = integer_value(state[:end])
                target_start = integer_value(target[:start])
                target_end = integer_value(target[:end])

                state_word.casecmp(target_word).zero? &&
                  state_start == target_start &&
                  state_end == target_end
              end

              def next_spell_scope(scopes, current_key)
                current_index = Array(scopes).index { |scope| scope[:key] == current_key }
                Array(scopes)[current_index ? (current_index + 1) % scopes.length : 0]
              end

              def spell_suggestions_for_scope(word, scope)
                spell_suggestions_from_matches(spell_ranked_matches_for_scope(word, scope))
              end

              def build_spell_scope_results(word, scopes)
                Array(scopes).each_with_index.map do |scope, index|
                  build_spell_scope_result(word, scope, index)
                end
              end

              def build_spell_scope_result(word, scope, index)
                matches = spell_ranked_matches_for_scope(word, scope)
                {
                  scope: scope,
                  scope_index: index,
                  matches: matches,
                  suggestions: spell_suggestions_from_matches(matches),
                }
              end

              def select_spell_scope_result(results, fallback_scope)
                return { scope: fallback_scope, suggestions: [] } if results.empty?

                populated = results.reject { |result| result[:suggestions].empty? }
                return results.first if populated.empty?

                populated.max_by { |result| spell_scope_result_rank(result) }
              end

              def spell_scope_result_rank(result)
                top_match = result[:matches].first
                [
                  top_match ? top_match[:similarity].to_f : -Float::INFINITY,
                  result[:suggestions].length,
                  -result[:scope_index],
                ]
              end

              def spell_match_candidates(word, scope)
                Array(scope[:strategies]).each_with_index.flat_map do |strategy, strategy_index|
                  build_spell_match_candidates(word, strategy, strategy_index)
                end
              end

              def build_spell_match_candidates(word, strategy, strategy_index)
                fetch_spell_matches(word, strategy).filter_map do |match|
                  build_spell_match_candidate(word, strategy, strategy_index, match)
                end
              end

              def build_spell_match_candidate(word, strategy, strategy_index, match)
                candidate = match.word.to_s.strip
                return nil if candidate.empty?
                return nil if candidate.casecmp(word).zero?

                {
                  word: candidate,
                  similarity: match.similarity.to_f,
                  strategy_index: strategy_index,
                  mode_rank: strategy[:mode] == :source ? 0 : 1,
                }
              end

              def sort_spell_matches(matches)
                Array(matches).sort_by do |match|
                  [
                    -match[:similarity],
                    match[:mode_rank],
                    match[:strategy_index],
                    match[:word].length,
                    match[:word].downcase,
                  ]
                end
              end

              def fetch_spell_matches(word, strategy)
                case strategy[:mode]
                when :source
                  source_spell_matches(word, strategy)
                when :translations
                  translation_spell_matches(word, strategy)
                else
                  []
                end
              end

              def source_spell_matches(word, strategy)
                Array(@dictionary_service.fuzzy_search(
                        word,
                        source_lang: strategy[:source],
                        target_lang: strategy[:target],
                        limit: SPELL_SUGGESTION_FETCH_LIMIT
                      ))
              end

              def translation_spell_matches(word, strategy)
                Array(@dictionary_service.fuzzy_search_translations(
                        word,
                        source_lang: strategy[:source],
                        target_lang: strategy[:target],
                        limit: SPELL_SUGGESTION_FETCH_LIMIT
                      ))
              end

              def integer_value(value)
                Shoko::Shared::TypeCoercion.optional_integer(value)
              end

              def normalize_spell_payload(payload)
                return payload unless payload.is_a?(Hash)

                payload.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
              end
            end
          end
        end
      end
    end
  end
end
