# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        class AnnotationOverlayController
          class SpellcheckCoordinator
            # Builds spellcheck lookup scopes from the available dictionary pairs.
            module LookupScopeSupport
              private

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
end
