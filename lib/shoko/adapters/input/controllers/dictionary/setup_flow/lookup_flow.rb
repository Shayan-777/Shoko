# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dictionary
          module SetupFlow
            # Entry-point orchestration for dictionary lookup and setup composition.
            module LookupFlow
              private

              def begin_lookup_with_setup(query:)
                pair_info = resolve_dictionary_pair(@dictionary_service)
                return lookup_available_pair(query, pair_info) if pair_info[:available]

                start_lookup_setup(
                  query: query,
                  source_hint: setup_source_language_hint,
                  target_default: configured_target_for_setup(pair_info[:target])
                )
              end

              def present_lookup_result(result, pair_info:)
                show_lookup_result_surface(result)
                notify_lookup_pair_status(pair_info)
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
                return unless setup_popup_ready?

                @setup_session = build_lookup_setup_session(
                  query: query,
                  source_hint: source_hint,
                  target_default: target_default
                )
                show_lookup_setup_popup(query: query, source_hint: source_hint)
                draw_dictionary_screen
              end

              def setup_popup_ready?
                ok = @dictionary_ui_session&.prepare_setup_popup
                return false unless session_ok?(ok)

                activate_dictionary_mode
                true
              end

              def lookup_available_pair(query, pair_info)
                result = @dictionary_service.lookup(
                  query,
                  source_lang: pair_info[:source],
                  target_lang: pair_info[:target]
                )
                present_lookup_result(result, pair_info: pair_info)
              end

              def show_lookup_result_surface(result)
                terminal_height, terminal_width = @terminal_service&.size || [24, 80]
                announce = result.search_mode != :unavailable

                if determine_dictionary_display_mode(terminal_width, terminal_height) == :panel
                  show_dictionary_panel(result, announce: announce)
                else
                  show_dictionary_popup(result, announce: announce)
                end
              end

              def notify_lookup_pair_status(pair_info)
                if pair_info[:fallback]
                  set_message("Dictionary: #{pair_info[:source].to_s.upcase} -> #{pair_info[:target].to_s.upcase}", 2)
                elsif missing_lookup_pair?(pair_info)
                  set_message("No dictionary for #{pair_info[:source]} -> #{pair_info[:target]}", 3)
                end
              end

              def missing_lookup_pair?(pair_info)
                !pair_info[:available] && pair_info[:available_pairs]&.any?
              end

              def build_lookup_setup_session(query:, source_hint:, target_default:)
                stage = source_hint ? :prompt_target : :prompt_source
                {
                  query: query.to_s,
                  stage: stage,
                  source_lang: source_hint,
                  source_input: source_hint ? source_hint.to_s : '',
                  target_lang: nil,
                  target_input: target_default.to_s,
                  source_suggestion_index: 0,
                  target_suggestion_index: 0,
                }
              end

              def show_lookup_setup_popup(query:, source_hint:)
                stage = @setup_session[:stage]
                @dictionary_ui_session.show_setup(**lookup_setup_popup_payload(query, source_hint, stage))
              end

              def lookup_setup_popup_payload(query, source_hint, stage)
                input_value = stage == :prompt_source ? @setup_session[:source_input] : @setup_session[:target_input]
                suggestions = setup_suggestions_for(stage: stage, source_lang: source_hint, input_value: input_value)
                {
                  stage: stage,
                  query: query.to_s,
                  source_lang: source_hint,
                  target_lang: nil,
                  input_value: input_value,
                  prompt: setup_prompt(stage, source_lang: source_hint),
                  status: stage == :prompt_source ? 'Source language could not be detected from metadata.' : '',
                  status_level: nil,
                  progress: 0.0,
                  suggestions: suggestions,
                  suggestion_index: 0,
                }
              end
            end
          end
        end
      end
    end
  end
end
