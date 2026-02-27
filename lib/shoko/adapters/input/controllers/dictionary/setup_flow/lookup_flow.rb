# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dictionary
          module SetupFlow
            # Entry-point orchestration for dictionary lookup and setup bootstrap.
            module LookupFlow
              private

              def begin_lookup_with_setup(query:)
                pair_info = resolve_dictionary_pair(@dictionary_service)
                if pair_info[:available]
                  result = @dictionary_service.lookup(query,
                                                      source_lang: pair_info[:source],
                                                      target_lang: pair_info[:target])
                  present_lookup_result(result, pair_info: pair_info)
                  return
                end

                source_hint = setup_source_language_hint
                target_default = configured_target_for_setup(pair_info[:target])
                start_lookup_setup(query: query, source_hint: source_hint, target_default: target_default)
              end

              def present_lookup_result(result, pair_info:)
                terminal_height, terminal_width = @terminal_service&.size || [24, 80]
                mode = determine_dictionary_display_mode(terminal_width, terminal_height)
                announce = result.search_mode != :unavailable
                if mode == :panel
                  show_dictionary_panel(result, announce: announce)
                else
                  show_dictionary_popup(result, announce: announce)
                end

                if pair_info[:fallback]
                  set_message("Dictionary: #{pair_info[:source].to_s.upcase} -> #{pair_info[:target].to_s.upcase}", 2)
                elsif !pair_info[:available] && pair_info[:available_pairs]&.any?
                  set_message("No dictionary for #{pair_info[:source]} -> #{pair_info[:target]}", 3)
                end
              end

              def configured_target_for_setup(fallback_target)
                normalize_dictionary_language(@config_reader.dictionary_target_lang) ||
                  normalize_dictionary_language(fallback_target) ||
                  @dictionary_service.configured_target_lang
              end

              def setup_source_language_hint
                explicit = normalize_dictionary_language(dictionary_book_metadata_language)
                return explicit if explicit

                remembered_manual_source_for_current_book
              end

              def start_lookup_setup(query:, source_hint:, target_default:)
                return unless ensure_setup_popup

                stage = source_hint ? :prompt_target : :prompt_source
                source_input = source_hint ? source_hint.to_s : ''
                target_input = target_default.to_s
                @setup_session = {
                  query: query.to_s,
                  stage: stage,
                  source_lang: source_hint,
                  source_input: source_input,
                  target_lang: nil,
                  target_input: target_input,
                  source_suggestion_index: 0,
                  target_suggestion_index: 0,
                }
                suggestions = setup_suggestions_for(stage: stage, source_lang: source_hint,
                                                    input_value: stage == :prompt_source ? source_input : target_input)

                @dictionary_ui_session.show_setup(
                  stage: stage,
                  query: query.to_s,
                  source_lang: source_hint,
                  target_lang: nil,
                  input_value: stage == :prompt_source ? source_input : target_input,
                  prompt: setup_prompt(stage, source_lang: source_hint),
                  status: stage == :prompt_source ? 'Source language could not be detected from metadata.' : '',
                  status_level: nil,
                  progress: 0.0,
                  suggestions: suggestions,
                  suggestion_index: 0
                )
                draw_dictionary_screen
              end

              def ensure_setup_popup
                ok = @dictionary_ui_session&.prepare_setup_popup
                return false unless session_ok?(ok)

                activate_dictionary_mode
                true
              end
            end
          end
        end
      end
    end
  end
end
