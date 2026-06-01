# frozen_string_literal: true

require_relative '../dictionary/constants'
require_relative '../support/message_notifier'
require_relative '../support/session_outcome_helpers'
require_relative '../../../../shared/type_coercion'

module Shoko
  module Adapters
    module Input
      module Controllers
        class AnnotationOverlayController
          # Handles annotation-editor spell suggestion lookup and cycling.
          class SpellcheckCoordinator
            include Shoko::Adapters::Input::Controllers::Support::MessageNotifier
            include Shoko::Adapters::Input::Controllers::Support::SessionOutcomeHelpers

            SPELL_SUGGESTION_LIMIT = 5
            SPELL_SUGGESTION_FETCH_LIMIT = 15
            BOUNDARY_ERRORS = [ArgumentError, TypeError, RuntimeError].freeze

            def initialize(dictionary_service:, ui_session:, notification_service:, logger:)
              @dictionary_service = dictionary_service
              @ui_session = ui_session
              @notification_service = notification_service
              @logger = logger
            end

            def run
              target = session_payload(@ui_session&.editor_spellcheck_target)
              word = spellcheck_word(target)
              scopes = spell_lookup_scopes
              return handle_missing_word unless word
              return handle_unavailable_dictionaries(target) unless @dictionary_service&.available?
              return handle_empty_scopes(target) if scopes.empty?

              lookup = resolve_spell_lookup(word, target, scopes)
              show_lookup(lookup, target, scopes)
              set_message(spellcheck_message(word, lookup[:scope], lookup[:suggestions]), 2)
              :handled
            rescue *BOUNDARY_ERRORS => e
              @logger&.debug("AnnotationOverlayController.annotation_editor_spellcheck failed: #{e.message}")
              set_message('Spell suggestions unavailable', 2)
              :handled
            end


            private

            def show_suggestions(**)
              @ui_session&.editor_show_spell_suggestions(**)
            end

            def spellcheck_word(target)
              return nil unless target.is_a?(Hash)

              word = target.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }[:word]
              normalized = word.to_s.strip
              normalized.empty? ? nil : normalized
            end

            def spell_language_label(language)
              Dictionary::Constants::LANGUAGE_LABELS[language] || language.to_s.upcase
            end

            def handle_missing_word
              show_suggestions(target: nil, suggestions: [])
              set_message('Place the cursor on a word to spell-check', 2)
              :handled
            end

            def handle_unavailable_dictionaries(target)
              show_suggestions(target: target, suggestions: [])
              set_message('Dictionary datasets unavailable for spell suggestions', 3)
              :handled
            end

            def handle_empty_scopes(target)
              show_suggestions(target: target, suggestions: [])
              set_message('No healthy dictionary datasets available for spell suggestions', 3)
              :handled
            end

            def show_lookup(lookup, target, scopes)
              scope = lookup[:scope]
              show_suggestions(
                target: target,
                suggestions: lookup[:suggestions],
                scope_key: scope[:key],
                scope_label: scope[:label],
                can_cycle: scopes.length > 1
              )
            end

            def spellcheck_message(word, scope, suggestions)
              return "No #{scope[:label]} suggestions for '#{word}'" if suggestions.empty?

              "Spelling suggestions for '#{word}' (#{scope[:label]})"
            end


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


            def spell_lookup_scopes
              pairs = available_spell_pairs
              return [] if pairs.empty?

              prioritized_spell_languages(pairs).filter_map { |language| build_spell_lookup_scope(language, pairs) }
            end

            def prioritized_spell_languages(pairs)
              normalize_languages(
                [
                  @dictionary_service&.configured_source_lang,
                  @dictionary_service&.configured_target_lang,
                  'de',
                  'en',
                ] + pairs.flat_map { |pair| [pair[:source], pair[:target]] }
              )
            end

            def normalize_languages(values)
              Array(values).filter_map { |value| normalize_language(value) }.uniq
            end

            def spell_lookup_strategies(language, pairs)
              target_priority = prioritized_spell_targets(language, pairs)
              source_spell_strategies(language, pairs, target_priority) +
                translation_spell_strategies(language, pairs, target_priority)
            end

            def prioritized_spell_targets(language, pairs)
              normalize_languages(
                [
                  @dictionary_service&.configured_target_lang,
                  @dictionary_service&.configured_source_lang,
                ] + pairs.flat_map { |pair| [pair[:source], pair[:target]] } - [language]
              )
            end

            def available_spell_pairs
              Array(@dictionary_service&.available_language_pairs).filter_map { |pair| normalize_pair(pair) }
            end

            def build_spell_lookup_scope(language, pairs)
              strategies = spell_lookup_strategies(language, pairs)
              return nil if strategies.empty?

              {
                key: "lang:#{language}",
                label: spell_language_label(language),
                strategies: strategies,
              }
            end

            def source_spell_strategies(language, pairs, target_priority)
              pairs
                .select { |pair| pair[:source] == language }
                .then { |language_pairs| sorted_spell_pairs(language_pairs, :target, target_priority) }
                .map { |pair| spell_lookup_strategy(:source, pair) }
            end

            def translation_spell_strategies(language, pairs, target_priority)
              pairs
                .select { |pair| pair[:target] == language }
                .then { |language_pairs| sorted_spell_pairs(language_pairs, :source, target_priority) }
                .map { |pair| spell_lookup_strategy(:translations, pair) }
            end

            def sorted_spell_pairs(pairs, priority_key, target_priority)
              Array(pairs).sort_by { |pair| spell_pair_priority(pair, priority_key, target_priority) }
            end

            def spell_pair_priority(pair, priority_key, target_priority)
              value = pair[priority_key]
              [target_priority.index(value) || target_priority.length, value]
            end

            def spell_lookup_strategy(mode, pair)
              { mode: mode, source: pair[:source], target: pair[:target] }
            end

            def normalize_pair(pair)
              return nil unless pair.is_a?(Hash)

              normalized = pair.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
              source = normalize_language(normalized[:source])
              target = normalize_language(normalized[:target])
              return nil if source.nil? || target.nil?

              { source: source, target: target }
            end

            def normalize_language(value)
              normalized = value.to_s.strip.downcase
              normalized.empty? ? nil : normalized
            end

          end
        end
      end
    end
  end
end
