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
              source_setting = @config_reader.dictionary_source_lang
              target_setting = @config_reader.dictionary_target_lang

              source = if dictionary_auto_setting?(source_setting)
                         normalize_dictionary_language(dictionary_book_language) || dictionary_service.configured_source_lang
                       else
                         normalize_dictionary_language(source_setting) || dictionary_service.configured_source_lang
                       end

              target = if dictionary_auto_setting?(target_setting)
                         dictionary_service.configured_target_lang
                       else
                         normalize_dictionary_language(target_setting) || dictionary_service.configured_target_lang
                       end

              available_pairs = dictionary_available_pairs(dictionary_service)
              selected = select_dictionary_pair(source, target, available_pairs)
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
                source = pair[:source] || pair['source']
                target = pair[:target] || pair['target']
                next if source.nil? || target.nil?

                {
                  source: normalize_dictionary_language(source),
                  target: normalize_dictionary_language(target),
                }
              end.uniq
            rescue Shoko::Error
              []
            end

            def select_dictionary_pair(source, target, pairs)
              if source && target && pairs.any? { |pair| pair[:source] == source && pair[:target] == target }
                return { source: source, target: target, available: true, fallback: false }
              end

              if source
                source_pairs = pairs.select { |pair| pair[:source] == source }
                if source_pairs.any?
                  candidate_targets = source_pairs.map { |pair| pair[:target] }
                  chosen_target = if target && candidate_targets.include?(target)
                                    target
                                  else
                                    candidate_targets.min
                                  end
                  return { source: source, target: chosen_target, available: true, fallback: chosen_target != target }
                end
              end

              { source: source, target: target, available: false, fallback: false }
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
            rescue Shoko::Error
              []
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
              text = input_value.to_s.strip.downcase
              norm = normalize_dictionary_language(text)
              base = codes
              return base if text.empty?

              matching = base.select do |code|
                label = setup_language_label(code).downcase
                code.start_with?(text) ||
                  code.start_with?(norm.to_s) ||
                  label.start_with?(text) ||
                  label.include?(text)
              end
              matching = base if matching.empty?

              matching.sort_by do |code|
                label = setup_language_label(code).downcase
                rank = if code == norm || code == text
                         0
                       elsif code.start_with?(text) || code.start_with?(norm.to_s)
                         1
                       elsif label.start_with?(text)
                         2
                       else
                         3
                       end
                [rank, code]
              end
            end

            def setup_language_label(code)
              Dictionary::Constants::LANGUAGE_LABELS[code.to_s.downcase] || code.to_s.upcase
            end

            def normalize_code_list(values)
              Array(values).filter_map { |value| normalize_dictionary_language(value) }.uniq
            end
          end
        end
      end
    end
  end
end
