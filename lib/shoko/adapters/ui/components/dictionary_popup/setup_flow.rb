# frozen_string_literal: true

require_relative '../../constants/ui_constants'
require_relative 'setup_rendering_support'
require_relative 'setup_state_support'
require_relative 'setup_text_support'

module Shoko
  module Adapters
    module Ui
      module Components
        module DictionaryPopup
          # Setup-state machine and setup rendering/key handling.
          module SetupFlow
            include Adapters::Ui::Constants::Ui
            include SetupRenderingSupport
            include SetupStateSupport
            include SetupTextSupport

            def show_setup(stage:, query:, source_lang: nil, target_lang: nil, input_value: '', prompt: nil,
                           status: nil, status_level: nil, progress: 0.0,
                           suggestions: nil, suggestion_index: 0)
              reset_result_mode_state!
              @setup_mode = true
              @setup_state = build_setup_state(stage: stage, query: query, source_lang: source_lang,
                                               target_lang: target_lang, input_value: input_value, prompt: prompt,
                                               status: status, status_level: status_level, progress: progress,
                                               suggestions: suggestions, suggestion_index: suggestion_index)
              clamp_setup_suggestion_index!
            end

            def update_setup(stage: nil, source_lang: nil, target_lang: nil, input_value: nil, prompt: nil,
                             status: nil, status_level: nil, progress: nil,
                             suggestions: nil, suggestion_index: nil)
              return unless @setup_mode

              updates = {
                stage: [stage, :to_sym],
                source_lang: [source_lang, nil],
                target_lang: [target_lang, nil],
                input_value: [input_value, :to_s],
                prompt: [prompt, :to_s],
                status: [status, :to_s],
                status_level: [status_level, :to_sym],
                progress: [progress, :to_f],
                suggestions: [suggestions, method(:normalize_setup_suggestions)],
                suggestion_index: [suggestion_index, :to_i],
              }
              apply_setup_updates(updates)
              clamp_setup_suggestion_index!
            end

            def setup_mode?
              @setup_mode
            end

            def handle_setup_key(key)
              return { type: :close } if close_setup_key?(key)

              navigation = setup_navigation_event(key)
              return navigation if navigation

              return nil if setup_stage == :downloading

              immediate = setup_immediate_event(key)
              return immediate if immediate

              return nil unless editable_setup_stage?

              setup_edit_event(key)
            end

            def reset_result_mode_state!
              @visible = true
              @result = nil
              @scroll_offset = 0
              @formatted_lines = []
              @entry_index = 0
              @fuzzy_mode = false
              @fuzzy_matches = []
            end

            def close_setup_key?(key)
              Shared::KeyDefinitions::ACTIONS[:cancel].include?(key) ||
                Shared::KeyDefinitions::ACTIONS[:quit].include?(key)
            end

            def setup_navigation_event(key)
              return emit_setup_selection(-1) if Shared::KeyDefinitions::NAVIGATION[:up].include?(key)
              return emit_setup_selection(1) if Shared::KeyDefinitions::NAVIGATION[:down].include?(key)

              nil
            end

            def setup_immediate_event(key)
              tab_event = setup_tab_event(key)
              return tab_event if tab_event
              return { type: :setup_swap } if setup_swap_key?(key)
              return { type: :setup_submit, stage: setup_stage, value: setup_input } if setup_confirm_key?(key)

              nil
            end

            def setup_tab_event(key)
              return nil unless key == "\t"

              suggestion = selected_setup_suggestion_code
              return nil unless suggestion

              update_setup_input(suggestion)
              { type: :setup_apply_suggestion, stage: setup_stage, value: suggestion }
            end

            def setup_swap_key?(key)
              key == 'S' && setup_stage == :prompt_target && !setup_source.empty?
            end

            def setup_confirm_key?(key)
              Shared::KeyDefinitions::ACTIONS[:confirm].include?(key)
            end

            def setup_edit_event(key)
              if Shared::KeyDefinitions::ACTIONS[:backspace].include?(key)
                update_setup_input(setup_input[0...-1].to_s)
                return { type: :setup_change, stage: setup_stage, value: setup_input }
              end

              return nil unless printable_input_char?(key)

              update_setup_input("#{setup_input}#{key}")
              { type: :setup_change, stage: setup_stage, value: setup_input }
            end
          end
        end
      end
    end
  end
end
