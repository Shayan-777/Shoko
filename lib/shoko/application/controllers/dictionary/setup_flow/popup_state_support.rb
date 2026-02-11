# frozen_string_literal: true

module Shoko
  module Application::Controllers
    module Dictionary
      module SetupFlow
        # Setup popup update and suggestion-index state helpers.
        module PopupStateSupport
          private

          def update_setup_popup(stage: nil, source_lang: nil, target_lang: nil, input_value: nil, prompt: nil,
                                 status: nil, status_level: nil, progress: nil,
                                 suggestions: nil, suggestion_index: nil, redraw: true)
            return unless ensure_setup_popup

            resolved_stage = (stage || @setup_session&.dig(:stage))&.to_sym
            resolved_source = source_lang.nil? ? @setup_session&.dig(:source_lang) : source_lang
            resolved_input = if input_value.nil?
                               case resolved_stage
                               when :prompt_source
                                 @setup_session&.dig(:source_input)
                               when :prompt_target
                                 @setup_session&.dig(:target_input)
                               end
                             else
                               input_value
                             end
            resolved_suggestions = suggestions
            resolved_suggestion_index = suggestion_index
            if %i[prompt_source prompt_target].include?(resolved_stage)
              resolved_suggestions ||= setup_suggestions_for(stage: resolved_stage, source_lang: resolved_source,
                                                             input_value: resolved_input)
              resolved_suggestion_index ||= setup_suggestion_index_for(resolved_stage, resolved_suggestions)
            end

            @dictionary_ui_session.update_setup(
              stage: stage,
              source_lang: source_lang,
              target_lang: target_lang,
              input_value: input_value,
              prompt: prompt,
              status: status,
              status_level: status_level,
              progress: progress,
              suggestions: resolved_suggestions,
              suggestion_index: resolved_suggestion_index
            )
            draw_dictionary_screen if redraw
          end

          def setup_error(message, stage:)
            source = @setup_session[:source_lang]
            target = @setup_session[:target_lang]
            input_value = stage == :prompt_source ? @setup_session[:source_input].to_s : @setup_session[:target_input].to_s
            update_setup_popup(
              stage: stage,
              source_lang: source,
              target_lang: target,
              input_value: input_value,
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
        end
      end
    end
  end
end
