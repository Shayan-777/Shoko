# frozen_string_literal: true

require 'shoko/core/policies/dictionary_language_setting'
require 'shoko/shared/hash_normalizer'
require_relative 'constants'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dictionary
          # Resolves dictionary language pairs and owns per-book manual source
          # choices used by the installation wizard.
          class LanguagePlanner
            def initialize(dictionary_service:, config_reader:, document:, reader_state:)
              @dictionary_service = dictionary_service
              @config_reader = config_reader
              @document = document
              @reader_state = reader_state
              @manual_source_by_book = {}
            end

            def resolve_pair
              pairs = available_pairs
              selected = exact_pair(resolved_source, resolved_target, pairs) ||
                         source_fallback_pair(resolved_source, resolved_target, pairs) ||
                         unavailable_pair(resolved_source, resolved_target)
              selected.merge(available_pairs: pairs)
            end

            def configured_target(fallback)
              normalize(@config_reader.dictionary_target_lang) ||
                normalize(fallback) ||
                @dictionary_service.configured_target_lang
            end

            def source_hint
              normalize(metadata_language) || remembered_source
            end

            def normalize(value)
              return nil if value.nil?

              raw = value.to_s.strip
              return nil if raw.empty?

              code = raw.downcase.tr(' ', '_').split(/[-_]/).first.to_s
              mapped = Constants::LANGUAGE_CODE_MAP[code]
              return mapped if mapped
              return code if code.match?(/\A[a-z]{2,3}\z/)

              nil
            end

            def suggestions(stage:, source_lang:, input_value:)
              codes = stage.to_sym == :prompt_source ? source_candidates : target_candidates(source_lang)
              filtered = filter_candidates(codes, input_value)
              filtered.first(8).map { |code| { code: code, label: language_label(code) } }
            end

            def remember_source(source_lang)
              key = book_key
              @manual_source_by_book[key] = source_lang if key
            end

            def remembered_source
              key = book_key
              key ? @manual_source_by_book[key] : nil
            end

            private

            def available_pairs
              Array(@dictionary_service.available_language_pairs).filter_map do |pair|
                normalized = normalize_pair_hash(pair)
                source = normalize(normalized[:source])
                target = normalize(normalized[:target])
                { source: source, target: target } if source && target
              end.uniq
            end

            def normalize_pair_hash(pair)
              unless pair.is_a?(Hash)
                raise Shoko::MalformedDictionaryInputError, "language pair must be Hash, got #{pair.class}"
              end

              Shoko::Shared::HashNormalizer.symbolize_keys(pair)
            end

            def resolved_source
              setting = @config_reader.dictionary_source_lang
              value = if Shoko::Core::Policies::DictionaryLanguageSetting.auto?(setting)
                        @document&.language
                      else
                        setting
                      end
              normalize(value) || @dictionary_service.configured_source_lang
            end

            def resolved_target
              setting = @config_reader.dictionary_target_lang
              value = Shoko::Core::Policies::DictionaryLanguageSetting.auto?(setting) ? nil : setting
              normalize(value) || @dictionary_service.configured_target_lang
            end

            def exact_pair(source, target, pairs)
              return unless source && target
              return unless pairs.any? { |pair| pair[:source] == source && pair[:target] == target }

              available_pair(source, target, fallback: false)
            end

            def source_fallback_pair(source, target, pairs)
              return unless source

              candidates = pairs.select { |pair| pair[:source] == source }
              return if candidates.empty?

              targets = candidates.map { |pair| pair[:target] }
              chosen = target && targets.include?(target) ? target : targets.min
              available_pair(source, chosen, fallback: chosen != target)
            end

            def available_pair(source, target, fallback:)
              { source: source, target: target, available: true, fallback: fallback }
            end

            def unavailable_pair(source, target)
              { source: source, target: target, available: false, fallback: false }
            end

            def source_candidates
              configured = @config_reader.dictionary_source_lang
              configured = nil if Shoko::Core::Policies::DictionaryLanguageSetting.auto?(configured)
              normalize_codes(
                [metadata_language, remembered_source, configured, @dictionary_service.configured_source_lang] +
                available_pairs.map { |pair| pair[:source] } + Constants::COMMON_SETUP_LANGS
              )
            end

            def target_candidates(source_lang)
              pairs = available_pairs
              source = normalize(source_lang)
              preferred = pairs.select { |pair| pair[:source] == source }.map { |pair| pair[:target] }
              normalize_codes(
                [@config_reader.dictionary_target_lang, @dictionary_service.configured_target_lang] +
                preferred + pairs.map { |pair| pair[:target] } + Constants::COMMON_SETUP_LANGS
              )
            end

            def normalize_codes(values)
              Array(values).filter_map { |value| normalize(value) }.uniq
            end

            def filter_candidates(codes, input_value)
              text = input_value.to_s.strip.downcase
              return codes if text.empty?

              normalized = normalize(text).to_s
              matching = codes.select { |code| candidate_matches?(code, text, normalized) }
              ranked(matching.empty? ? codes : matching, text, normalized)
            end

            def candidate_matches?(code, text, normalized)
              label = language_label(code).downcase
              code.start_with?(text, normalized) || label.start_with?(text) || label.include?(text)
            end

            def ranked(codes, text, normalized)
              codes.sort_by { |code| [candidate_rank(code, text, normalized), code] }
            end

            def candidate_rank(code, text, normalized)
              label = language_label(code).downcase
              return 0 if code == normalized || code == text
              return 1 if code.start_with?(text, normalized)
              return 2 if label.start_with?(text)

              3
            end

            def language_label(code)
              Constants::LANGUAGE_LABELS[code.to_s.downcase] || code.to_s.upcase
            end

            def metadata_language
              metadata = @document&.metadata
              return nil unless metadata.is_a?(Hash)

              value = metadata[:language].to_s.strip
              value.empty? ? nil : value
            end

            def book_key
              value = (@reader_state.book_path || @document&.source_path).to_s.strip
              value.empty? ? nil : value
            end
          end
        end
      end
    end
  end
end
