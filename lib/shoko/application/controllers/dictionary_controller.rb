# frozen_string_literal: true

require_relative 'dictionary/index'

module Shoko
  module Application::Controllers
    # Handles dictionary lookups and dictionary UI lifecycle.
    class DictionaryController
      include Dictionary::ControllerSupport
      include Dictionary::DisplayModeSupport
      include Dictionary::LanguagePairSupport
      include Dictionary::SetupFlowSupport

      def initialize(reader_state:, config_reader:, sidebar_state:, state_writer:,
                     layout_metrics: nil, dictionary_service: nil,
                     dictionary_catalog_service: nil, dictionary_availability: nil, dictionary_storage: nil,
                     terminal_service: nil, ui_component_factory: nil, logger: nil,
                     input_controller: nil, layout_service: nil, reader_controller: nil,
                     document: nil, selection_service: nil, rendered_content_reader: nil,
                     notification_service: nil, settings_service: nil, ui_controller: nil, clock: nil,
                     dictionary_ui_session: nil)
        @reader_state = reader_state
        @config_reader = config_reader
        @sidebar_state = sidebar_state
        @state_writer = state_writer
        @layout_metrics = layout_metrics
        @dictionary_service = dictionary_service
        @dictionary_catalog_service = dictionary_catalog_service
        @dictionary_availability = dictionary_availability
        @dictionary_storage = dictionary_storage
        @terminal_service = terminal_service
        @ui_component_factory_inst = ui_component_factory
        @logger = logger
        @input_controller = input_controller
        @layout_service = layout_service
        @reader_controller = reader_controller
        @document = document
        @selection_service = selection_service
        @rendered_content_reader = rendered_content_reader
        @notification_service = notification_service
        @settings_service = settings_service
        @ui_controller = ui_controller
        raise ArgumentError, 'clock is required' if clock.nil?

        @clock = clock
        @dictionary_ui_session = dictionary_ui_session
        @manual_source_lang_by_book = {}
        @setup_session = nil
      end

      # Setter injection for circular dependency resolution — set after construction
      attr_writer :input_controller

      def handle_lookup_action(action_data)
        selection_range = if action_data.is_a?(Hash)
                            action_data[:data][:selection_range]
                          else
                            @reader_state.selection
                          end

        selected_text = extract_selected_text_from_selection(selection_range)

        if selected_text.nil? || selected_text.strip.empty?
          set_message('No text selected for lookup')
          cleanup_popup_state
          return
        end

        lookup_word = extract_lookup_word(selected_text)

        unless @dictionary_service
          set_message('Dictionary service not available')
          cleanup_popup_state
          return
        end

        @state_writer.update_reader(popup_menu: nil)
        begin_lookup_with_setup(query: lookup_word)
      end

      def show_dictionary_panel(result, announce: true)
        outcome = @dictionary_ui_session&.show_panel(result)
        return unless session_ok?(outcome)

        @setup_session = nil
        activate_dictionary_mode
        set_message("Looking up '#{result.query}'", 2) if announce
      end

      def show_dictionary_popup(result, announce: true)
        outcome = @dictionary_ui_session&.show_popup(result)
        return unless session_ok?(outcome)

        @setup_session = nil
        activate_dictionary_mode
        set_message("Looking up '#{result.query}'", 2) if announce
      end

      def close_dictionary
        @dictionary_ui_session&.close
        @setup_session = nil
        @state_writer.clear_selection
        deactivate_dictionary_mode
      end

      def dictionary_insert_char(char)
        result = session_payload(@dictionary_ui_session&.insert_char(char))
        process_dictionary_session_result(result)
      end

      def dictionary_backspace(_key = nil)
        result = session_payload(@dictionary_ui_session&.backspace)
        process_dictionary_session_result(result)
      end

      def dictionary_confirm(_key = nil)
        result = session_payload(@dictionary_ui_session&.confirm)
        process_dictionary_session_result(result)
      end

      def dictionary_cancel(_key = nil)
        result = session_payload(@dictionary_ui_session&.cancel)
        process_dictionary_session_result(result)
      end

      def dictionary_tab(_key = nil)
        result = session_payload(@dictionary_ui_session&.tab)
        process_dictionary_session_result(result)
      end

      def dictionary_swap_languages(_key = nil)
        result = session_payload(@dictionary_ui_session&.swap_languages)
        process_dictionary_session_result(result)
      end

      def process_dictionary_session_result(result)
        return :pass unless result

        case result[:type]
        when :close
          close_dictionary
          :handled
        when :scroll
          :handled
        when :setup_change
          handle_setup_change(result)
          :handled
        when :setup_select
          handle_setup_select(result)
          :handled
        when :setup_apply_suggestion
          handle_setup_apply_suggestion(result)
          :handled
        when :setup_swap
          handle_setup_swap
          :handled
        when :setup_submit
          handle_setup_submit(result)
          :handled
        else
          :pass
        end
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

        result = @dictionary_ui_session&.active_result
        return :pass unless result

        if @dictionary_ui_session.fuzzy_mode?
          session_ok?(@dictionary_ui_session.toggle_fuzzy)
        else
          return :pass unless @dictionary_service

          matches = @dictionary_service.fuzzy_search(result.query,
                                                     source_lang: result.source_lang,
                                                     target_lang: result.target_lang)
          session_ok?(@dictionary_ui_session.toggle_fuzzy(matches))
        end

        :handled
      end

      def dictionary_cycle_result(_key = nil)
        if @dictionary_ui_session&.setup_mode?
          outcome = dictionary_tab
          return outcome == :pass ? :handled : outcome
        end
        return :pass if @dictionary_ui_session&.fuzzy_mode?

        session_ok?(@dictionary_ui_session&.next_entry) ? :handled : :pass
      end

      def dictionary_cycle_pair(_key = nil)
        return :handled if @dictionary_ui_session&.setup_mode?
        result = @dictionary_ui_session&.active_result
        return :pass unless result

        return :pass unless @settings_service && @dictionary_service

        @settings_service.cycle_dictionary_pair
        pair_info = resolve_dictionary_pair(@dictionary_service)
        new_result = @dictionary_service.lookup(result.query,
                                                source_lang: pair_info[:source],
                                                target_lang: pair_info[:target])

        if @dictionary_ui_session.active_kind == :panel
          show_dictionary_panel(new_result, announce: false)
        else
          show_dictionary_popup(new_result, announce: false)
        end

        set_message("Dictionary: #{pair_info[:source].to_s.upcase} -> #{pair_info[:target].to_s.upcase}", 2)
        :handled
      end

      def active_dictionary_component
        @dictionary_ui_session&.active_kind
      end

      def dictionary_visible?
        @dictionary_ui_session&.visible? == true
      end

      private

      def session_payload(result)
        return result unless session_outcome?(result)

        result.payload
      end

      def session_ok?(result)
        return result.ok if session_outcome?(result)

        !!result
      end

      def session_outcome?(result)
        result.is_a?(Shoko::Application::Ui::SessionOutcome)
      end
    end
  end
end
