# frozen_string_literal: true

module Shoko
  module Application::Controllers
    module Dictionary
      module SetupFlow
        # Handles setup submit semantics and transition to lookup/download.
        module SubmissionFlow
          private

          def submit_setup_source(raw_value)
            source_input = effective_setup_submit_value(:prompt_source, raw_value)
            source = normalize_dictionary_language(source_input)
            unless source
              setup_error('Please enter a valid source language (for example: en, de, fr).', stage: :prompt_source)
              return
            end

            @setup_session[:source_lang] = source
            @setup_session[:source_input] = source
            remember_manual_source_for_current_book(source)
            @setup_session[:stage] = :prompt_target
            update_setup_popup(
              stage: :prompt_target,
              source_lang: source,
              target_lang: nil,
              input_value: @setup_session[:target_input],
              prompt: setup_prompt(:prompt_target, source_lang: source),
              status: '',
              status_level: nil,
              progress: 0.0
            )
          end

          def submit_setup_target(raw_value)
            target_input = effective_setup_submit_value(:prompt_target, raw_value)
            target = normalize_dictionary_language(target_input)
            unless target
              setup_error('Please enter a valid target language (for example: en, de, fr).', stage: :prompt_target)
              return
            end

            source = @setup_session[:source_lang]
            unless source
              setup_error('Source language is required.', stage: :prompt_source)
              return
            end

            @setup_session[:target_lang] = target
            @setup_session[:target_input] = target
            persist_target_language(target)

            if @dictionary_service.language_pair_available?(source, target)
              complete_lookup_after_setup(source, target)
            else
              download_pair_for_setup(source, target)
            end
          end

          def complete_lookup_after_setup(source, target)
            query = @setup_session[:query].to_s
            result = @dictionary_service.lookup(query, source_lang: source, target_lang: target)
            pair_info = { source: source, target: target, fallback: false, available: true, available_pairs: [] }
            present_lookup_result(result, pair_info: pair_info)
          end

          def setup_prompt(stage, source_lang:)
            case stage
            when :prompt_source
              'Enter source language code (for example: en, de, fr).'
            when :prompt_target
              source_text = source_lang.to_s.strip
              "Enter target language code for #{source_text.upcase}."
            else
              ''
            end
          end

          def effective_setup_submit_value(stage, raw_value)
            text = raw_value.to_s.strip
            return text if stage.to_sym == :prompt_source
            return text unless text.empty?

            suggestions = setup_suggestions_for(stage: stage, source_lang: @setup_session[:source_lang], input_value: text)
            index = setup_suggestion_index_for(stage, suggestions)
            suggestions[index]&.dig(:code).to_s
          rescue StandardError
            text
          end

          def persist_target_language(target)
            @state_writer.update_config(dictionary_target_lang: target)
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
