# frozen_string_literal: true

require_relative 'dependencies/dictionary_controller_dependencies'
require_relative 'dictionary/index'
require_relative 'support/session_outcome_helpers'
require_relative 'support/message_notifier'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Handles dictionary lookups and dictionary UI lifecycle.
        class DictionaryController
          include Shoko::Adapters::Input::Controllers::Support::SessionOutcomeHelpers

          Dependencies = Shoko::Adapters::Input::Controllers::Dependencies::DictionaryControllerDependencies::Bundle

          include Dictionary::LanguagePairSupport
          include Dictionary::SetupFlowSupport

          def initialize(deps:)
            dependencies = deps.validate!
            assign_state_dependencies(dependencies.state)
            assign_service_dependencies(dependencies.services)
            assign_ui_dependencies(dependencies.ui)
            assign_controller_dependencies(dependencies.controllers)
            @manual_source_lang_by_book = {}
            @setup_session = nil
          end

          # Open the "Dictionary" bar. A selection payload (from the popup "Look Up")
          # pre-fills the query and defines it immediately; the `d` hotkey (nil
          # payload) opens an empty bar to type into.
          def open_dictionary_lookup(payload = nil)
            return service_unavailable unless @dictionary_service

            outcome = @dictionary_ui_session&.open
            return :pass unless session_ok?(outcome)

            activate_dictionary_mode
            prefill_and_define(payload)
            :handled
          rescue Shoko::Error => e
            @logger&.debug("DictionaryController.open_dictionary_lookup failed: #{e.message}")
            :pass
          end

          def submit_dictionary_lookup
            query = @reader_state.dictionary_query.to_s.strip
            return :handled if query.empty?
            return service_unavailable unless @dictionary_service

            begin_lookup_with_setup(query: query)
            :handled
          rescue Shoko::Error => e
            @logger&.debug("DictionaryController.submit_dictionary_lookup failed: #{e.message}")
            :pass
          end

          # Publish a lookup result to the definition card (the single result
          # surface; replaces the old centered popup / right-side panel).
          def show_dictionary_lookup(result, announce: true)
            outcome = @dictionary_ui_session&.apply_result(result)
            return unless session_ok?(outcome)

            @setup_session = nil
            activate_dictionary_mode
            set_message("Looking up '#{result.query}'", 2) if announce
          end

          def close_dictionary_lookup(_key = nil)
            @dictionary_ui_session&.close
            @setup_session = nil
            @reader_session_mutator.clear_selection
            deactivate_dictionary_mode
            :handled
          end

          include Shoko::Adapters::Input::Controllers::Support::MessageNotifier

          def dictionary_insert_char(char)
            process_session_action(@dictionary_ui_session&.insert_char(char))
          end

          def dictionary_backspace(_key = nil)
            process_session_action(@dictionary_ui_session&.backspace)
          end

          def dictionary_confirm(_key = nil)
            process_session_action(@dictionary_ui_session&.confirm)
          end

          def dictionary_tab(_key = nil)
            process_session_action(@dictionary_ui_session&.tab)
          end

          def dictionary_swap_languages(_key = nil)
            return process_session_action(@dictionary_ui_session&.swap_languages) if @dictionary_ui_session&.setup_mode?

            swap_lookup_languages
          end

          def process_dictionary_session_result(result)
            return :pass unless result

            handle_primary_session_result(result) || handle_setup_session_result(result) || :pass
          end

          def dictionary_scroll_up(_key = nil)
            process_session_action(@dictionary_ui_session&.scroll_up)
          end

          def dictionary_scroll_down(_key = nil)
            process_session_action(@dictionary_ui_session&.scroll_down)
          end

          def dictionary_toggle_fuzzy(_key = nil)
            return :handled if @dictionary_ui_session&.setup_mode?

            result = @reader_state.dictionary_result
            return :pass unless result

            if @reader_state.dictionary_fuzzy_mode
              @dictionary_ui_session&.clear_fuzzy
            else
              return :pass unless @dictionary_service

              matches = @dictionary_service.fuzzy_search(
                result.query,
                source_lang: result.source_lang,
                target_lang: result.target_lang
              )
              @dictionary_ui_session&.apply_fuzzy(matches)
            end

            :handled
          end

          def dictionary_cycle_result(_key = nil)
            advance_dictionary_entry
          end

          def dictionary_cycle_pair(_key = nil)
            return :handled if @dictionary_ui_session&.setup_mode?

            result = cycle_pair_result
            return :pass unless result

            refresh_dictionary_pair_result(result)
          end

          def dictionary_visible?
            @dictionary_ui_session&.visible? == true
          end

          def refresh_theme(theme_context:)
            color_mode = theme_context&.color_mode
            @dictionary_ui_session&.refresh_theme(color_mode: color_mode)
          end

          private

          def assign_state_dependencies(deps)
            @reader_state = deps.reader_state
            @config_reader = deps.config_reader
            @reader_session_mutator = deps.reader_session_mutator
            @document = deps.document
            @rendered_content_reader = deps.rendered_content_reader
          end

          def assign_service_dependencies(deps)
            @dictionary_service = deps.dictionary_service
            @dictionary_catalog_service = deps.dictionary_catalog_service
            @dictionary_availability = deps.dictionary_availability
            @dictionary_storage = deps.dictionary_storage
            @selection_service = deps.selection_service
            @notification_service = deps.notification_service
            @settings_service = deps.settings_service
          end

          def assign_ui_dependencies(deps)
            @layout_metrics = deps.layout_metrics
            @terminal_service = deps.terminal_service
            @ui_component_factory_inst = deps.ui_component_factory
            @dictionary_ui_session = deps.dictionary_ui_session
          end

          def assign_controller_dependencies(deps)
            @logger = deps.logger
            @input_controller = deps.input_controller
            @layout_service = deps.layout_service
            @reader_controller = deps.reader_controller
            @ui_controller = deps.ui_controller
            @clock = deps.clock
          end

          def prefill_and_define(payload)
            word = selection_lookup_word(payload)
            if word && !word.empty?
              @reader_session_mutator.update_reader(dictionary_query: word)
              submit_dictionary_lookup
            else
              set_message('Dictionary: type a word, then Enter to define', 2)
            end
          end

          def selection_lookup_word(payload)
            return nil unless payload.is_a?(Hash)

            selected_text = extract_selected_text_from_selection(selection_range_for(payload))
            return nil if selected_text.nil? || selected_text.strip.empty?

            extract_lookup_word(selected_text)
          end

          def selection_range_for(payload)
            payload.dig(:data, :selection_range) || @reader_state.selection
          end

          def reject_lookup(message)
            set_message(message)
            cleanup_popup_state
            nil
          end

          def service_unavailable
            set_message('Dictionary service not available')
            :pass
          end

          def dictionary_book_metadata_language
            metadata = @document&.metadata
            return nil unless metadata.is_a?(Hash)

            value = metadata[:language]
            raw = value.to_s.strip
            return nil if raw.empty?

            raw
          end

          def remembered_manual_source_for_current_book
            key = current_book_memory_key
            return nil unless key

            @manual_source_lang_by_book[key]
          end

          def remember_manual_source_for_current_book(source_lang)
            key = current_book_memory_key
            return unless key

            @manual_source_lang_by_book[key] = source_lang
          end

          def current_book_memory_key
            path = @reader_state.book_path || @document&.source_path
            text = path.to_s.strip
            return nil if text.empty?

            text
          end

          def draw_dictionary_screen
            @reader_controller&.draw_screen
          end

          def extract_lookup_word(text)
            cleaned = text.to_s.strip.gsub(/\s+/, ' ')
            words = cleaned.split
            if words.length <= 3
              cleaned
            else
              words.first
            end
          end

          def activate_dictionary_mode
            @input_controller&.enter_modal_mode(:dictionary)
          end

          def deactivate_dictionary_mode
            @input_controller&.exit_modal_mode(:dictionary)
          end

          def dictionary_book_language
            @document&.language
          end

          def extract_selected_text_from_selection(selection_range)
            return nil unless @selection_service && @rendered_content_reader

            rendered_lines = @rendered_content_reader.rendered_lines
            @selection_service.extract_text(selection_range, rendered_lines)
          end

          def cleanup_popup_state
            @ui_controller&.cleanup_popup_state
          rescue Shoko::Error
            # Best effort.
          end

          def process_session_action(outcome)
            process_dictionary_session_result(session_payload(outcome))
          end

          def handle_primary_session_result(result)
            case result[:type]
            when :close
              close_dictionary_lookup
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
            @reader_session_mutator.update_reader(dictionary_entry_index: next_index, dictionary_selected_index: 0)
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
            show_dictionary_lookup(new_result, announce: false)
            set_message("Dictionary: #{pair_info[:source].to_s.upcase} -> #{pair_info[:target].to_s.upcase}", 2)
            :handled
          end

          # S in lookup mode: flip source/target and define again.
          def swap_lookup_languages
            result = @reader_state.dictionary_result
            return :pass unless result && @dictionary_service

            source = result.target_lang.to_s
            target = result.source_lang.to_s
            return :pass if source.empty? || target.empty?

            new_result = @dictionary_service.lookup(result.query, source_lang: source, target_lang: target)
            show_dictionary_lookup(new_result, announce: false)
            set_message("Dictionary: #{source.upcase} -> #{target.upcase}", 2)
            :handled
          end
        end
      end
    end
  end
end
