# frozen_string_literal: true

module Shoko
  module Adapters::Input::Controllers
    module Dictionary
      module SetupFlow
        # Handles setup-stage input events emitted by dictionary UI components.
        module InteractionHandlers
          private

          def handle_setup_change(result)
            return unless @setup_session

            stage = result[:stage]&.to_sym
            value = result[:value].to_s
            case stage
            when :prompt_source
              @setup_session[:source_input] = value
              @setup_session[:source_suggestion_index] = 0
            when :prompt_target
              @setup_session[:target_input] = value
              @setup_session[:target_suggestion_index] = 0
            end

            update_setup_popup(stage: stage, status: '', status_level: nil, input_value: value)
          end

          def handle_setup_select(result)
            return unless @setup_session

            stage = result[:stage]&.to_sym
            return unless %i[prompt_source prompt_target].include?(stage)

            index = result[:index].to_i
            set_setup_suggestion_index(stage, index)
            update_setup_popup(stage: stage, redraw: true)
          end

          def handle_setup_apply_suggestion(result)
            return unless @setup_session

            stage = result[:stage]&.to_sym
            value = result[:value].to_s
            return unless %i[prompt_source prompt_target].include?(stage)

            case stage
            when :prompt_source
              @setup_session[:source_input] = value
            when :prompt_target
              @setup_session[:target_input] = value
            end
            update_setup_popup(stage: stage, input_value: value, status: '', status_level: nil)
          end

          def handle_setup_swap
            return unless @setup_session
            return unless @setup_session[:stage] == :prompt_target

            target_candidate = normalize_dictionary_language(@setup_session[:target_input])
            unless target_candidate
              setup_error('Cannot swap yet. Enter/select a valid target language first.', stage: :prompt_target)
              return
            end

            old_source = @setup_session[:source_lang]
            @setup_session[:source_lang] = target_candidate
            @setup_session[:source_input] = target_candidate
            remember_manual_source_for_current_book(target_candidate)

            @setup_session[:target_input] = old_source.to_s
            @setup_session[:target_lang] = nil
            @setup_session[:target_suggestion_index] = 0

            update_setup_popup(
              stage: :prompt_target,
              source_lang: target_candidate,
              target_lang: nil,
              input_value: @setup_session[:target_input],
              prompt: setup_prompt(:prompt_target, source_lang: target_candidate),
              status: 'Swapped source/target. Pick the new target language.',
              status_level: nil,
              progress: 0.0
            )
          end

          def handle_setup_submit(result)
            return unless @setup_session

            stage = result[:stage]&.to_sym
            value = result[:value].to_s
            case stage
            when :prompt_source
              submit_setup_source(value)
            when :prompt_target
              submit_setup_target(value)
            end
          end
        end
      end
    end
  end
end
