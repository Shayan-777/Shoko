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
                     dictionary_catalog_service: nil, dictionary_availability: nil,
                     terminal_service: nil, ui_component_factory: nil, logger: nil,
                     input_controller: nil, layout_service: nil, reader_controller: nil,
                     document: nil, selection_service: nil, rendered_content_reader: nil,
                     notification_service: nil, settings_service: nil, ui_controller: nil)
        @reader_state = reader_state
        @config_reader = config_reader
        @sidebar_state = sidebar_state
        @state_writer = state_writer
        @layout_metrics = layout_metrics
        @dictionary_service = dictionary_service
        @dictionary_catalog_service = dictionary_catalog_service
        @dictionary_availability = dictionary_availability
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
        panel = @reader_state.dictionary_panel
        panel ||= ui_component_factory&.dictionary_panel(@reader_state)
        return unless panel

        @setup_session = nil
        popup = @reader_state.dictionary_popup
        popup&.hide
        panel.show(result)
        @state_writer.update_reader(
          dictionary_panel: panel,
          dictionary_popup: nil,
          dictionary_visible: true,
          mode: :dictionary
        )
        activate_dictionary_mode
        set_message("Looking up '#{result.query}'", 2) if announce
      end

      def show_dictionary_popup(result, announce: true)
        popup = @reader_state.dictionary_popup
        popup ||= ui_component_factory&.dictionary_popup
        return unless popup

        @setup_session = nil
        panel = @reader_state.dictionary_panel
        panel&.hide
        popup.show(result)
        @state_writer.update_reader(
          dictionary_panel: nil,
          dictionary_popup: popup,
          dictionary_visible: true,
          mode: :dictionary
        )
        activate_dictionary_mode
        set_message("Looking up '#{result.query}'", 2) if announce
      end

      def close_dictionary
        panel = @reader_state.dictionary_panel
        popup = @reader_state.dictionary_popup

        panel&.hide
        popup&.hide
        @setup_session = nil

        @state_writer.update_reader(
          dictionary_panel: nil,
          dictionary_popup: nil,
          dictionary_visible: false,
          mode: :read
        )
        @state_writer.clear_selection
        deactivate_dictionary_mode
      end

      def handle_dictionary_key(key)
        component = active_dictionary_component
        return :pass unless component

        result = component.handle_key(key)
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
        panel = @reader_state.dictionary_panel
        popup = @reader_state.dictionary_popup
        return unless panel&.visible? || popup&.visible?

        result = panel&.visible? ? panel.result : popup&.result
        return unless result

        mode = determine_dictionary_display_mode(terminal_width, terminal_height)
        if mode == :panel && !panel&.visible?
          show_dictionary_panel(result, announce: false)
        elsif mode == :popup && !popup&.visible?
          show_dictionary_popup(result, announce: false)
        end
      end

      def dictionary_scroll_up(_key = nil)
        handle_dictionary_key("\e[A")
        :handled
      end

      def dictionary_scroll_down(_key = nil)
        handle_dictionary_key("\e[B")
        :handled
      end

      def dictionary_toggle_fuzzy(_key = nil)
        component = active_dictionary_component
        return :handled if component.respond_to?(:setup_mode?) && component.setup_mode?
        return :pass unless component.respond_to?(:toggle_fuzzy)

        result = component.result
        return :pass unless result

        if component.respond_to?(:fuzzy_mode?) && component.fuzzy_mode?
          component.toggle_fuzzy
        else
          return :pass unless @dictionary_service

          matches = @dictionary_service.fuzzy_search(result.query,
                                                     source_lang: result.source_lang,
                                                     target_lang: result.target_lang)
          component.toggle_fuzzy(matches)
        end

        :handled
      end

      def dictionary_cycle_result(_key = nil)
        component = active_dictionary_component
        if component.respond_to?(:setup_mode?) && component.setup_mode?
          outcome = handle_dictionary_key("\t")
          return outcome == :pass ? :handled : outcome
        end
        return :pass unless component.respond_to?(:next_entry)
        return :pass if component.respond_to?(:fuzzy_mode?) && component.fuzzy_mode?

        component.next_entry ? :handled : :pass
      end

      def dictionary_cycle_pair(_key = nil)
        component = active_dictionary_component
        return :handled if component.respond_to?(:setup_mode?) && component.setup_mode?
        result = component&.result
        return :pass unless result

        return :pass unless @settings_service && @dictionary_service

        @settings_service.cycle_dictionary_pair
        pair_info = resolve_dictionary_pair(@dictionary_service)
        new_result = @dictionary_service.lookup(result.query,
                                                source_lang: pair_info[:source],
                                                target_lang: pair_info[:target])

        if dictionary_panel_component?(component)
          show_dictionary_panel(new_result, announce: false)
        else
          show_dictionary_popup(new_result, announce: false)
        end

        set_message("Dictionary: #{pair_info[:source].to_s.upcase} -> #{pair_info[:target].to_s.upcase}", 2)
        :handled
      end

      def active_dictionary_component
        panel = @reader_state.dictionary_panel
        popup = @reader_state.dictionary_popup
        panel&.visible? ? panel : popup
      end
    end
  end
end
