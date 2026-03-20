# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module DictionaryPopup
          # State mutation and normalization helpers for dictionary popup setup mode.
          module SetupStateSupport
            private

            def build_setup_state(stage:, query:, source_lang:, target_lang:, input_value:, prompt:, status:,
                                  status_level:, progress:, suggestions:, suggestion_index:)
              {
                stage: stage&.to_sym || :prompt_target,
                query: query.to_s,
                source_lang: source_lang,
                target_lang: target_lang,
                input_value: input_value.to_s,
                prompt: prompt.to_s,
                status: status.to_s,
                status_level: status_level&.to_sym,
                progress: progress.to_f,
                suggestions: normalize_setup_suggestions(suggestions),
                suggestion_index: suggestion_index.to_i,
              }
            end

            def apply_setup_updates(updates)
              updates.each do |key, payload|
                assign_setup_value(key, payload[0], payload[1])
              end
            end

            def assign_setup_value(key, value, converter = nil)
              return if value.nil?

              @setup_state[key] = convert_setup_value(value, converter)
            end

            def convert_setup_value(value, converter)
              return value unless converter
              return converter.call(value) if converter.respond_to?(:call)

              value.public_send(converter)
            end

            def setup_stage
              (@setup_state[:stage] || :prompt_target).to_sym
            end

            def setup_source
              @setup_state[:source_lang].to_s.strip
            end

            def setup_target
              @setup_state[:target_lang].to_s.strip
            end

            def setup_input
              @setup_state[:input_value].to_s
            end

            def setup_suggestions
              normalize_setup_suggestions(@setup_state[:suggestions])
            end

            def setup_suggestion_index
              clamp_setup_suggestion_index!
              @setup_state[:suggestion_index].to_i
            end

            def selected_setup_suggestion
              items = setup_suggestions
              return nil if items.empty?

              items[setup_suggestion_index]
            end

            def selected_setup_suggestion_code
              selected_setup_suggestion&.dig(:code).to_s
            end

            def editable_setup_stage?
              %i[prompt_source prompt_target].include?(setup_stage)
            end

            def update_setup_input(value)
              @setup_state[:input_value] = value.to_s
            end

            def emit_setup_selection(delta)
              return nil unless editable_setup_stage?

              items = setup_suggestions
              return nil if items.empty?

              index = setup_suggestion_index
              index = (index + delta.to_i) % items.length
              @setup_state[:suggestion_index] = index
              { type: :setup_select, stage: setup_stage, index: index, value: items[index][:code] }
            end

            def normalize_setup_suggestions(items)
              normalized = Array(items).filter_map { |item| normalize_setup_suggestion(item) }
              normalized.uniq { |entry| entry[:code] }
            end

            def normalize_setup_suggestion(item)
              return normalize_setup_suggestion_hash(item) if item.is_a?(Hash)

              normalize_setup_suggestion_scalar(item)
            end

            def normalize_setup_suggestion_hash(item)
              normalized = item.transform_keys do |key|
                key.is_a?(String) ? key.to_sym : key
              end
              code = normalized[:code]
              label = normalized[:label] || code
              code_text = code.to_s.strip.downcase
              return nil if code_text.empty?

              { code: code_text, label: label.to_s.strip }
            end

            def normalize_setup_suggestion_scalar(item)
              code_text = item.to_s.strip.downcase
              return nil if code_text.empty?

              { code: code_text, label: code_text.upcase }
            end

            def clamp_setup_suggestion_index!
              items = setup_suggestions
              max = [items.length - 1, 0].max
              idx = @setup_state[:suggestion_index].to_i
              idx = 0 if idx.negative?
              idx = max if idx > max
              @setup_state[:suggestion_index] = idx
            end

            def printable_input_char?(key)
              return false unless key.is_a?(String)
              return false unless key.length == 1

              codepoint = key.ord
              codepoint >= 32 && codepoint != 127
            end
          end
        end
      end
    end
  end
end
