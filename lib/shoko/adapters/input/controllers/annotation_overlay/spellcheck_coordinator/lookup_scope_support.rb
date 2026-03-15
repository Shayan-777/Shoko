# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        class AnnotationOverlayController
          class SpellcheckCoordinator
            module LookupScopeSupport
              private

              def spell_lookup_scopes
                pairs = Array(@dictionary_service&.available_language_pairs).filter_map { |pair| normalize_pair(pair) }
                return [] if pairs.empty?

                prioritized_spell_languages(pairs).filter_map do |language|
                  strategies = spell_lookup_strategies(language, pairs)
                  next if strategies.empty?

                  {
                    key: "lang:#{language}",
                    label: spell_language_label(language),
                    strategies: strategies,
                  }
                end
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
                source_strategies = pairs
                                    .select { |pair| pair[:source] == language }
                                    .sort_by { |pair| [target_priority.index(pair[:target]) || target_priority.length, pair[:target]] }
                                    .map { |pair| { mode: :source, source: pair[:source], target: pair[:target] } }
                translation_strategies = pairs
                                         .select { |pair| pair[:target] == language }
                                         .sort_by { |pair| [target_priority.index(pair[:source]) || target_priority.length, pair[:source]] }
                                         .map { |pair| { mode: :translations, source: pair[:source], target: pair[:target] } }

                source_strategies + translation_strategies
              end

              def prioritized_spell_targets(language, pairs)
                normalize_languages(
                  [
                    @dictionary_service&.configured_target_lang,
                    @dictionary_service&.configured_source_lang,
                  ] + pairs.flat_map { |pair| [pair[:source], pair[:target]] } - [language]
                )
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
