# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dictionary
          # Language normalization, pair selection, and setup suggestion helpers.
          module LanguagePairSupport
            private

            def resolve_dictionary_pair(dictionary_service)
              available_pairs = dictionary_available_pairs(dictionary_service)
              selected = select_dictionary_pair(
                resolved_dictionary_source(dictionary_service),
                resolved_dictionary_target(dictionary_service),
                available_pairs
              )
              selected[:available_pairs] = available_pairs
              selected
            end

            def dictionary_auto_setting?(value)
              return true if value.nil?

              str = value.to_s.strip
              str.empty? || str.casecmp('auto').zero?
            end

            def dictionary_available_pairs(dictionary_service)
              pairs = dictionary_service.available_language_pairs
              Array(pairs).filter_map do |pair|
                normalized = normalize_pair_hash(pair)
                source = normalized[:source]
                target = normalized[:target]
                next if source.nil? || target.nil?

                {
                  source: normalize_dictionary_language(source),
                  target: normalize_dictionary_language(target),
                }
              end.uniq
            end

            def select_dictionary_pair(source, target, pairs)
              exact_dictionary_pair(source, target, pairs) ||
                source_fallback_dictionary_pair(source, target, pairs) ||
                unavailable_dictionary_pair(source, target)
            end

            def normalize_dictionary_language(value)
              return nil if value.nil?

              raw = value.to_s.strip
              return nil if raw.empty?

              code = raw.downcase.tr(' ', '_').split(/[-_]/).first.to_s
              mapped = Dictionary::Constants::LANGUAGE_CODE_MAP[code]
              return mapped if mapped

              return code if code.match?(/\A[a-z]{2,3}\z/)

              nil
            end

            def setup_suggestions_for(stage:, source_lang:, input_value:)
              codes = case stage.to_sym
                      when :prompt_source
                        source_setup_candidate_codes
                      when :prompt_target
                        target_setup_candidate_codes(source_lang)
                      else
                        []
                      end
              filtered = filter_setup_candidate_codes(codes, input_value)
              filtered.first(8).map { |code| { code: code, label: setup_language_label(code) } }
            end

            def normalize_pair_hash(pair)
              unless pair.is_a?(Hash)
                raise Shoko::MalformedDictionaryInputError, "language pair must be Hash, got #{pair.class}"
              end

              pair.each_with_object({}) do |(key, value), acc|
                normalized_key = key.is_a?(String) ? key.to_sym : key
                acc[normalized_key] = value
              end
            end

            def source_setup_candidate_codes
              configured_source = @config_reader.dictionary_source_lang
              configured_source = nil if dictionary_auto_setting?(configured_source)
              normalize_code_list(
                [
                  dictionary_book_metadata_language,
                  remembered_manual_source_for_current_book,
                  configured_source,
                  @dictionary_service&.configured_source_lang,
                ] +
                dictionary_available_pairs(@dictionary_service).map { |pair| pair[:source] } +
                Dictionary::Constants::COMMON_SETUP_LANGS
              )
            end

            def target_setup_candidate_codes(source_lang)
              pairs = dictionary_available_pairs(@dictionary_service)
              source = normalize_dictionary_language(source_lang)
              for_source = pairs.select { |pair| pair[:source] == source }.map { |pair| pair[:target] }
              fallbacks = pairs.map { |pair| pair[:target] }

              normalize_code_list(
                [
                  @config_reader.dictionary_target_lang,
                  @dictionary_service&.configured_target_lang,
                ] +
                for_source +
                fallbacks +
                Dictionary::Constants::COMMON_SETUP_LANGS
              )
            end

            def filter_setup_candidate_codes(codes, input_value)
              text, normalized = normalized_setup_filter(input_value)
              return codes if text.empty?

              matching = codes.select { |code| setup_candidate_matches?(code, text, normalized) }
              ranked_setup_candidate_codes(matching.empty? ? codes : matching, text, normalized)
            end

            def setup_language_label(code)
              Dictionary::Constants::LANGUAGE_LABELS[code.to_s.downcase] || code.to_s.upcase
            end

            def normalize_code_list(values)
              Array(values).filter_map { |value| normalize_dictionary_language(value) }.uniq
            end

            def resolved_dictionary_source(dictionary_service)
              value = dictionary_configured_source_value
              normalize_dictionary_language(value) || dictionary_service.configured_source_lang
            end

            def resolved_dictionary_target(dictionary_service)
              value = dictionary_configured_target_value
              normalize_dictionary_language(value) || dictionary_service.configured_target_lang
            end

            def dictionary_configured_source_value
              source_setting = @config_reader.dictionary_source_lang
              dictionary_auto_setting?(source_setting) ? dictionary_book_language : source_setting
            end

            def dictionary_configured_target_value
              target_setting = @config_reader.dictionary_target_lang
              dictionary_auto_setting?(target_setting) ? nil : target_setting
            end

            def exact_dictionary_pair(source, target, pairs)
              return unless source && target
              return unless pairs.any? { |pair| pair[:source] == source && pair[:target] == target }

              available_dictionary_pair(source, target, fallback: false)
            end

            def source_fallback_dictionary_pair(source, target, pairs)
              return unless source

              source_pairs = pairs.select { |pair| pair[:source] == source }
              return if source_pairs.empty?

              chosen_target = choose_dictionary_target(target, source_pairs)
              available_dictionary_pair(source, chosen_target, fallback: chosen_target != target)
            end

            def choose_dictionary_target(target, source_pairs)
              candidate_targets = source_pairs.map { |pair| pair[:target] }
              return target if target && candidate_targets.include?(target)

              candidate_targets.min
            end

            def available_dictionary_pair(source, target, fallback:)
              { source: source, target: target, available: true, fallback: fallback }
            end

            def unavailable_dictionary_pair(source, target)
              { source: source, target: target, available: false, fallback: false }
            end

            def normalized_setup_filter(input_value)
              text = input_value.to_s.strip.downcase
              [text, normalize_dictionary_language(text).to_s]
            end

            def setup_candidate_matches?(code, text, normalized)
              label = setup_language_label(code).downcase
              code.start_with?(text, normalized) ||
                label.start_with?(text) ||
                label.include?(text)
            end

            def ranked_setup_candidate_codes(codes, text, normalized)
              codes.sort_by { |code| [setup_candidate_rank(code, text, normalized), code] }
            end

            def setup_candidate_rank(code, text, normalized)
              label = setup_language_label(code).downcase
              return 0 if code == normalized || code == text
              return 1 if code.start_with?(text, normalized)
              return 2 if label.start_with?(text)

              3
            end
          end
        end
      end
    end
  end
end
