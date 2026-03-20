# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dictionary
          module SetupFlow
            # Setup popup update and suggestion-index state helpers.
            module PopupStateSupport
              private

              def update_setup_popup(stage: nil, source_lang: nil, target_lang: nil, input_value: nil, prompt: nil,
                                     status: nil, status_level: nil, progress: nil,
                                     suggestions: nil, suggestion_index: nil, redraw: true)
                return unless setup_popup_ready?

                outcome = update_setup_session(
                  stage: stage,
                  source_lang: source_lang,
                  target_lang: target_lang,
                  input_value: input_value,
                  prompt: prompt,
                  status: status,
                  status_level: status_level,
                  progress: progress,
                  suggestions: suggestions,
                  suggestion_index: suggestion_index
                )
                return unless session_ok?(outcome)

                draw_dictionary_screen if redraw
              end

              def setup_error(message, stage:)
                source = @setup_session[:source_lang]
                target = @setup_session[:target_lang]
                update_setup_popup(
                  stage: stage,
                  source_lang: source,
                  target_lang: target,
                  input_value: setup_error_input_value(stage),
                  prompt: setup_prompt(stage, source_lang: source),
                  status: message,
                  status_level: :error,
                  progress: 0.0
                )
              end

              def setup_suggestion_index_key(stage)
                stage.to_sym == :prompt_source ? :source_suggestion_index : :target_suggestion_index
              end

              def set_setup_suggestion_index(stage, index)
                return unless @setup_session

                key = setup_suggestion_index_key(stage)
                @setup_session[key] = index.to_i
              end

              def setup_suggestion_index_for(stage, suggestions)
                return 0 unless @setup_session

                key = setup_suggestion_index_key(stage)
                idx = @setup_session[key].to_i
                max = [Array(suggestions).length - 1, 0].max
                idx = 0 if idx.negative?
                idx = max if idx > max
                @setup_session[key] = idx
                idx
              end

              def setup_popup_payload(**attributes)
                resolved_stage, resolved_source, resolved_input = resolve_setup_popup_state(
                  attributes[:stage],
                  attributes[:source_lang],
                  attributes[:input_value]
                )
                resolved_suggestions, resolved_suggestion_index = resolve_setup_suggestions(
                  stage: resolved_stage,
                  source_lang: resolved_source,
                  input_value: resolved_input,
                  suggestions: attributes[:suggestions],
                  suggestion_index: attributes[:suggestion_index]
                )
                build_setup_popup_payload(attributes, resolved_suggestions, resolved_suggestion_index)
              end

              def update_setup_session(**)
                @dictionary_ui_session.update_setup(**setup_popup_payload(**))
              end

              def build_setup_popup_payload(attributes, suggestions, suggestion_index)
                attributes.merge(suggestions: suggestions, suggestion_index: suggestion_index)
              end

              def resolve_setup_popup_state(stage, source_lang, input_value)
                resolved_stage = (stage || @setup_session&.dig(:stage))&.to_sym
                resolved_source = source_lang.nil? ? @setup_session&.dig(:source_lang) : source_lang
                [resolved_stage, resolved_source, resolve_setup_input_value(resolved_stage, input_value)]
              end

              def resolve_setup_input_value(stage, input_value)
                return input_value unless input_value.nil?

                case stage
                when :prompt_source
                  @setup_session&.dig(:source_input)
                when :prompt_target
                  @setup_session&.dig(:target_input)
                end
              end

              def resolve_setup_suggestions(stage:, source_lang:, input_value:, suggestions:, suggestion_index:)
                return [suggestions, suggestion_index] unless %i[prompt_source prompt_target].include?(stage)

                resolved_suggestions = suggestions || setup_suggestions_for(
                  stage: stage,
                  source_lang: source_lang,
                  input_value: input_value
                )
                resolved_index = suggestion_index || setup_suggestion_index_for(stage, resolved_suggestions)
                [resolved_suggestions, resolved_index]
              end

              def setup_error_input_value(stage)
                return @setup_session[:source_input].to_s if stage == :prompt_source

                @setup_session[:target_input].to_s
              end
            end
          end
        end
      end
    end
  end
end
