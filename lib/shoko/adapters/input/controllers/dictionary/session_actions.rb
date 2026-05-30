# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dictionary
          # Owns interactive dictionary session commands and result transitions.
          module SessionActions
            def dictionary_insert_char(char)
              process_session_action(@dictionary_ui_session&.insert_char(char))
            end

            def dictionary_backspace(_key = nil)
              process_session_action(@dictionary_ui_session&.backspace)
            end

            def dictionary_confirm(_key = nil)
              process_session_action(@dictionary_ui_session&.confirm)
            end

            def dictionary_cancel(_key = nil)
              process_session_action(@dictionary_ui_session&.cancel)
            end

            def dictionary_tab(_key = nil)
              process_session_action(@dictionary_ui_session&.tab)
            end

            def dictionary_swap_languages(_key = nil)
              process_session_action(@dictionary_ui_session&.swap_languages)
            end

            def process_dictionary_session_result(result)
              return :pass unless result

              handle_primary_session_result(result) || handle_setup_session_result(result) || :pass
            end

            def refresh_dictionary_display_mode(terminal_width:, terminal_height:)
              return unless @dictionary_ui_session&.visible?

              result = @dictionary_ui_session.active_result
              return unless result

              mode = determine_dictionary_display_mode(terminal_width, terminal_height)
              if mode == :panel && !@dictionary_ui_session.panel_visible?
                show_dictionary_panel(result, announce: false)
              elsif mode == :popup && !@dictionary_ui_session.popup_visible?
                show_dictionary_popup(result, announce: false)
              end
            end

            def dictionary_scroll_up(_key = nil)
              session_ok?(@dictionary_ui_session&.scroll_up) ? :handled : :pass
            end

            def dictionary_scroll_down(_key = nil)
              session_ok?(@dictionary_ui_session&.scroll_down) ? :handled : :pass
            end

            def dictionary_toggle_fuzzy(_key = nil)
              return :handled if @dictionary_ui_session&.setup_mode?

              result = @reader_state.dictionary_result
              return :pass unless result

              if @reader_state.dictionary_fuzzy_mode
                @reader_session_mutator.update_reader(dictionary_fuzzy_mode: false, dictionary_fuzzy_matches: [])
              else
                return :pass unless @dictionary_service

                matches = @dictionary_service.fuzzy_search(
                  result.query,
                  source_lang: result.source_lang,
                  target_lang: result.target_lang
                )
                @reader_session_mutator.update_reader(dictionary_fuzzy_mode: true, dictionary_fuzzy_matches: matches)
              end

              :handled
            end

            def dictionary_cycle_result(_key = nil)
              if @dictionary_ui_session&.setup_mode?
                outcome = dictionary_tab
                return outcome == :pass ? :handled : outcome
              end

              advance_dictionary_entry
            end

            def dictionary_cycle_pair(_key = nil)
              return :handled if @dictionary_ui_session&.setup_mode?

              result = cycle_pair_result
              return :pass unless result

              refresh_dictionary_pair_result(result)
            end

            def active_dictionary_component
              @dictionary_ui_session&.active_kind
            end

            def dictionary_visible?
              @dictionary_ui_session&.visible? == true
            end

            def refresh_theme(theme_context:)
              color_mode = theme_context&.color_mode
              @dictionary_ui_session&.refresh_theme(color_mode: color_mode)
            end

            private

            def process_session_action(outcome)
              process_dictionary_session_result(session_payload(outcome))
            end

            def handle_primary_session_result(result)
              case result[:type]
              when :close
                close_dictionary
                :handled
              when :scroll
                :handled
              end
            end

            def handle_setup_session_result(result)
              case result[:type]
              when :setup_change
                handle_setup_change(result)
              when :setup_select
                handle_setup_select(result)
              when :setup_apply_suggestion
                handle_setup_apply_suggestion(result)
              when :setup_swap
                handle_setup_swap
              when :setup_submit
                handle_setup_submit(result)
              else
                return
              end

              :handled
            end

            def cycle_pair_result
              return if @reader_state.dictionary_fuzzy_mode

              result = @reader_state.dictionary_result
              return unless result && @settings_service && @dictionary_service

              result
            end

            def advance_dictionary_entry
              return :pass if @reader_state.dictionary_fuzzy_mode

              result = @reader_state.dictionary_result
              return :pass unless result.respond_to?(:entry_count) && result.entry_count > 1

              next_index = (@reader_state.dictionary_entry_index.to_i + 1) % result.entry_count
              @reader_session_mutator.update_reader(dictionary_entry_index: next_index)
              :handled
            end

            def refresh_dictionary_pair_result(result)
              @settings_service.cycle_dictionary_pair
              pair_info = resolve_dictionary_pair(@dictionary_service)
              new_result = @dictionary_service.lookup(
                result.query,
                source_lang: pair_info[:source],
                target_lang: pair_info[:target]
              )
              display_dictionary_pair_result(new_result)
              set_message("Dictionary: #{pair_info[:source].to_s.upcase} -> #{pair_info[:target].to_s.upcase}", 2)
              :handled
            end

            def display_dictionary_pair_result(result)
              if @dictionary_ui_session.active_kind == :panel
                show_dictionary_panel(result, announce: false)
              else
                show_dictionary_popup(result, announce: false)
              end
            end
          end
        end
      end
    end
  end
end
