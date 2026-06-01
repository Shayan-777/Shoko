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

          def handle_lookup_action(action_data)
            lookup_word = lookup_word_for_action(action_data)
            return reject_lookup('No text selected for lookup') if lookup_word.nil? || lookup_word.empty?
            return reject_lookup('Dictionary service not available') unless @dictionary_service

            @reader_session_mutator.update_reader(popup_menu: nil)
            begin_lookup_with_setup(query: lookup_word)
          end

          def show_dictionary_panel(result, announce: true)
            outcome = @dictionary_ui_session&.show_panel(result)
            return unless session_ok?(outcome)

            @setup_session = nil
            @reader_controller&.rebuild_root_layout
            activate_dictionary_mode
            set_message("Looking up '#{result.query}'", 2) if announce
          end

          def show_dictionary_popup(result, announce: true)
            outcome = @dictionary_ui_session&.show_popup(result)
            return unless session_ok?(outcome)

            @setup_session = nil
            @reader_controller&.rebuild_root_layout
            activate_dictionary_mode
            set_message("Looking up '#{result.query}'", 2) if announce
          end

          def close_dictionary
            @dictionary_ui_session&.close
            @setup_session = nil
            @reader_session_mutator.clear_selection
            @reader_controller&.rebuild_root_layout
            deactivate_dictionary_mode
          end


          include Shoko::Adapters::Input::Controllers::Support::MessageNotifier


          def determine_dictionary_display_mode(terminal_width, terminal_height)
            min_terminal = dictionary_panel_min_terminal_width
            return :popup if terminal_width < min_terminal

            available_right = dictionary_available_right_space(terminal_width, terminal_height)
            min_width = dictionary_panel_min_width
            return :panel if available_right >= min_width

            :popup
          rescue Shoko::Error => e
            @logger&.debug("DictionaryController.determine_dictionary_display_mode failed: #{e.message}")
            :popup
          end


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

          def assign_state_dependencies(deps)
            @reader_state = deps.reader_state
            @config_reader = deps.config_reader
            @sidebar_state = deps.sidebar_state
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

          def lookup_word_for_action(action_data)
            selected_text = extract_selected_text_from_selection(selection_range_for(action_data))
            return nil if selected_text.nil? || selected_text.strip.empty?

            extract_lookup_word(selected_text)
          end

          def selection_range_for(action_data)
            return @reader_state.selection unless action_data.is_a?(Hash)

            action_data.dig(:data, :selection_range)
          end

          def reject_lookup(message)
            set_message(message)
            cleanup_popup_state
            nil
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

          def ui_component_factory
            @ui_component_factory_inst
          end

          def dictionary_panel_component?(component)
            factory = ui_component_factory
            factory ? factory.dictionary_panel_component?(component) : false
          end

          def dictionary_panel_min_terminal_width
            factory = ui_component_factory
            factory ? factory.dictionary_panel_min_terminal_width : 1_000_000
          end

          def dictionary_panel_min_width
            factory = ui_component_factory
            factory ? factory.dictionary_panel_min_width : 1_000_000
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


          def dictionary_available_right_space(terminal_width, terminal_height)
            sidebar_width = sidebar_width_for(terminal_width, terminal_height)
            main_width = terminal_width - sidebar_width
            return 0 if main_width <= 0

            view_mode = @config_reader.view_mode || :single
            col_width = resolved_column_width(main_width, terminal_height, view_mode)
            absolute_right_edge = sidebar_width + content_right_edge_for(main_width, col_width, view_mode)
            [terminal_width - absolute_right_edge, 0].max
          end

          def sidebar_width_for(terminal_width, terminal_height)
            return 0 unless @sidebar_state.sidebar_visible?

            sidebar_bounds = @reader_controller&.render_coordinator&.sidebar_bounds(terminal_width, terminal_height)
            return sidebar_bounds.width if sidebar_bounds&.width

            0
          rescue Shoko::Error => e
            @logger&.debug("DictionaryController.sidebar_width_for failed: #{e.message}")
            0
          end

          def resolved_column_width(main_width, terminal_height, view_mode)
            col_width, = @layout_service&.calculate_metrics(main_width, terminal_height, view_mode)
            col_width || (view_mode == :split ? (main_width / 2) : main_width)
          end

          def content_right_edge_for(main_width, col_width, view_mode)
            return split_content_right_edge(col_width) if view_mode == :split

            centered_content_right_edge(main_width, col_width)
          end

          def split_content_right_edge(col_width)
            left_start = @layout_metrics.split_left_margin + 1
            right_start = left_start + col_width + @layout_metrics.split_column_gap
            right_start + col_width - 1
          end

          def centered_content_right_edge(main_width, col_width)
            col_start = [(main_width - col_width) / 2, 1].max
            col_start + col_width - 1
          end


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
