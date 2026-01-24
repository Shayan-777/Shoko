# frozen_string_literal: true

require_relative '../../adapters/output/ui/components/dictionary_panel_component'
require_relative '../../adapters/output/ui/components/dictionary_popup_component'

module Shoko
  module Application::Controllers
    # Handles all dictionary-related functionality: lookups, panel/popup display, language pairs
    class DictionaryController
      def initialize(state, dependencies)
        @state = state
        @dependencies = dependencies
        @layout_metrics = resolve_layout_metrics
      end

      def handle_lookup_action(action_data)
        selection_range = if action_data.is_a?(Hash)
                            action_data[:data][:selection_range]
                          else
                            @state.get(%i[reader selection])
                          end

        selected_text = extract_selected_text_from_selection(selection_range)

        if selected_text.nil? || selected_text.strip.empty?
          set_message('No text selected for lookup')
          cleanup_popup_state
          return
        end

        lookup_word = extract_lookup_word(selected_text)

        dictionary_service = safe_resolve(:dictionary_service)
        unless dictionary_service
          set_message('Dictionary service not available')
          cleanup_popup_state
          return
        end

        pair_info = resolve_dictionary_pair(dictionary_service)
        result = dictionary_service.lookup(lookup_word,
                                           source_lang: pair_info[:source],
                                           target_lang: pair_info[:target])

        terminal_service = safe_resolve(:terminal_service)
        terminal_height, terminal_width = terminal_service&.size || [24, 80]

        mode = determine_dictionary_display_mode(terminal_width, terminal_height)
        announce = result.search_mode != :unavailable
        mode == :panel ? show_dictionary_panel(result, announce: announce) : show_dictionary_popup(result, announce: announce)

        if pair_info[:fallback]
          set_message("Dictionary: #{pair_info[:source].to_s.upcase} -> #{pair_info[:target].to_s.upcase}", 2)
        elsif !pair_info[:available] && pair_info[:available_pairs]&.any?
          set_message("No dictionary for #{pair_info[:source]} -> #{pair_info[:target]}", 3)
        end

        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(popup_menu: nil))
      end

      def show_dictionary_panel(result, announce: true)
        panel = @state.get(%i[reader dictionary_panel])
        panel ||= Shoko::Adapters::Output::Ui::Components::DictionaryPanelComponent.new(@state)
        popup = @state.get(%i[reader dictionary_popup])
        popup&.hide
        panel.show(result)
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(
                          dictionary_panel: panel,
                          dictionary_popup: nil,
                          dictionary_visible: true,
                          mode: :dictionary
                        ))
        activate_dictionary_mode
        set_message("Looking up '#{result.query}'", 2) if announce
      end

      def show_dictionary_popup(result, announce: true)
        popup = @state.get(%i[reader dictionary_popup])
        popup ||= Shoko::Adapters::Output::Ui::Components::DictionaryPopupComponent.new
        panel = @state.get(%i[reader dictionary_panel])
        panel&.hide
        popup.show(result)
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(
                          dictionary_panel: nil,
                          dictionary_popup: popup,
                          dictionary_visible: true,
                          mode: :dictionary
                        ))
        activate_dictionary_mode
        set_message("Looking up '#{result.query}'", 2) if announce
      end

      def close_dictionary
        panel = @state.get(%i[reader dictionary_panel])
        popup = @state.get(%i[reader dictionary_popup])

        panel&.hide
        popup&.hide

        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(
                          dictionary_panel: nil,
                          dictionary_popup: nil,
                          dictionary_visible: false,
                          mode: :read
                        ))
        @state.dispatch(Shoko::Application::Actions::ClearSelectionAction.new)
        deactivate_dictionary_mode
      end

      def handle_dictionary_key(key)
        component = active_dictionary_component
        return unless component

        result = component.handle_key(key)
        return unless result

        case result[:type]
        when :close
          close_dictionary
        when :scroll
          # Just redraw, component handles scroll state
        end
      end

      def refresh_dictionary_display_mode(terminal_width:, terminal_height:)
        panel = @state.get(%i[reader dictionary_panel])
        popup = @state.get(%i[reader dictionary_popup])
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
        handle_dictionary_key("\e[A") # Simulate up arrow
        :handled
      end

      def dictionary_scroll_down(_key = nil)
        handle_dictionary_key("\e[B") # Simulate down arrow
        :handled
      end

      def dictionary_toggle_fuzzy(_key = nil)
        component = active_dictionary_component
        return :pass unless component&.respond_to?(:toggle_fuzzy)

        result = component.result
        return :pass unless result

        if component.respond_to?(:fuzzy_mode?) && component.fuzzy_mode?
          component.toggle_fuzzy
        else
          dictionary_service = safe_resolve(:dictionary_service)
          return :pass unless dictionary_service

          matches = dictionary_service.fuzzy_search(result.query,
                                                    source_lang: result.source_lang,
                                                    target_lang: result.target_lang)
          component.toggle_fuzzy(matches)
        end

        :handled
      end

      def dictionary_cycle_result(_key = nil)
        component = active_dictionary_component
        return :pass unless component&.respond_to?(:next_entry)
        return :pass if component.respond_to?(:fuzzy_mode?) && component.fuzzy_mode?

        component.next_entry ? :handled : :pass
      end

      def dictionary_cycle_pair(_key = nil)
        component = active_dictionary_component
        result = component&.result
        return :pass unless result

        settings_service = safe_resolve(:settings_service)
        dictionary_service = safe_resolve(:dictionary_service)
        return :pass unless settings_service && dictionary_service

        settings_service.cycle_dictionary_pair
        pair_info = resolve_dictionary_pair(dictionary_service)
        new_result = dictionary_service.lookup(result.query,
                                               source_lang: pair_info[:source],
                                               target_lang: pair_info[:target])

        if component.is_a?(Shoko::Adapters::Output::Ui::Components::DictionaryPanelComponent)
          show_dictionary_panel(new_result, announce: false)
        else
          show_dictionary_popup(new_result, announce: false)
        end

        set_message("Dictionary: #{pair_info[:source].to_s.upcase} -> #{pair_info[:target].to_s.upcase}", 2)
        :handled
      end

      def active_dictionary_component
        panel = @state.get(%i[reader dictionary_panel])
        popup = @state.get(%i[reader dictionary_popup])
        panel&.visible? ? panel : popup
      end

      def determine_dictionary_display_mode(terminal_width, terminal_height)
        min_terminal = Shoko::Adapters::Output::Ui::Components::DictionaryPanelComponent::MIN_TERMINAL_WIDTH
        return :popup if terminal_width < min_terminal

        available_right = dictionary_available_right_space(terminal_width, terminal_height)
        min_width = Shoko::Adapters::Output::Ui::Components::DictionaryPanelComponent::MIN_WIDTH
        return :panel if available_right >= min_width

        :popup
      rescue StandardError
        :popup
      end

      private

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
        input_controller = safe_resolve(:input_controller)
        input_controller&.enter_modal_mode(:dictionary)
      end

      def deactivate_dictionary_mode
        input_controller = safe_resolve(:input_controller)
        input_controller&.exit_modal_mode(:dictionary)
      end

      def dictionary_available_right_space(terminal_width, terminal_height)
        sidebar_width = sidebar_width_for(terminal_width, terminal_height)
        main_width = terminal_width - sidebar_width
        return 0 if main_width <= 0

        layout_service = safe_resolve(:layout_service)
        view_mode = @state.get(%i[config view_mode]) || :split
        col_width, = layout_service&.calculate_metrics(main_width, terminal_height, view_mode)
        col_width ||= view_mode == :split ? (main_width / 2) : main_width

        content_right_edge = if view_mode == :split
                               left_start = @layout_metrics.split_left_margin + 1
                               right_start = left_start + col_width + @layout_metrics.split_column_gap
                               right_start + col_width - 1
                             else
                               col_start = [(main_width - col_width) / 2, 1].max
                               col_start + col_width - 1
                             end

        absolute_right_edge = sidebar_width + content_right_edge
        [terminal_width - absolute_right_edge, 0].max
      end

      def sidebar_width_for(terminal_width, terminal_height)
        return 0 unless @state.get(%i[reader sidebar_visible])

        reader_controller = safe_resolve(:reader_controller)
        sidebar_bounds = reader_controller&.render_coordinator&.sidebar_bounds(terminal_width, terminal_height)
        return sidebar_bounds.width if sidebar_bounds&.width

        0
      rescue StandardError
        0
      end

      def resolve_dictionary_pair(dictionary_service)
        source_setting = @state.get(%i[config dictionary_source_lang])
        target_setting = @state.get(%i[config dictionary_target_lang])

        source = if dictionary_auto_setting?(source_setting)
                   normalize_dictionary_language(dictionary_book_language) || dictionary_service.configured_source_lang
                 else
                   normalize_dictionary_language(source_setting) || dictionary_service.configured_source_lang
                 end

        target = if dictionary_auto_setting?(target_setting)
                   dictionary_service.configured_target_lang
                 else
                   normalize_dictionary_language(target_setting) || dictionary_service.configured_target_lang
                 end

        available_pairs = dictionary_available_pairs(dictionary_service)
        selected = select_dictionary_pair(source, target, available_pairs)
        selected[:available_pairs] = available_pairs
        selected
      end

      def dictionary_book_language
        doc = safe_resolve(:document)
        doc&.language
      end

      def dictionary_auto_setting?(value)
        return true if value.nil?

        str = value.to_s.strip
        str.empty? || str.casecmp('auto').zero?
      end

      def dictionary_available_pairs(dictionary_service)
        pairs = dictionary_service.available_language_pairs
        Array(pairs).filter_map do |pair|
          source = pair[:source] || pair['source']
          target = pair[:target] || pair['target']
          next if source.nil? || target.nil?

          {
            source: normalize_dictionary_language(source),
            target: normalize_dictionary_language(target),
          }
        end.uniq
      rescue StandardError
        []
      end

      def select_dictionary_pair(source, target, pairs)
        if source && target && pairs.any? { |pair| pair[:source] == source && pair[:target] == target }
          return { source: source, target: target, available: true, fallback: false }
        end

        if source
          source_pairs = pairs.select { |pair| pair[:source] == source }
          if source_pairs.any?
            candidate_targets = source_pairs.map { |pair| pair[:target] }
            chosen_target = if target && candidate_targets.include?(target)
                              target
                            else
                              candidate_targets.sort.first
                            end
            return { source: source, target: chosen_target, available: true, fallback: chosen_target != target }
          end
        end

        { source: source, target: target, available: false, fallback: false }
      end

      def normalize_dictionary_language(value)
        return nil if value.nil?

        raw = value.to_s.strip
        return nil if raw.empty?

        code = raw.split(/[-_]/).first.to_s.downcase
        map = {
          'eng' => 'en',
          'deu' => 'de',
          'ger' => 'de',
          'rus' => 'ru',
          'zho' => 'zh',
          'chi' => 'zh',
        }
        map.fetch(code, code)
      end

      def extract_selected_text_from_selection(selection_range)
        selection_service = @dependencies.resolve(:selection_service)
        rendered_content_reader = @dependencies.resolve(:rendered_content_reader)
        if selection_service.respond_to?(:extract_from_state)
          selection_service.extract_from_state(@state, rendered_content_reader: rendered_content_reader, selection_range: selection_range)
        else
          rendered_lines = rendered_content_reader.rendered_lines
          selection_service.extract_text(selection_range, rendered_lines)
        end
      end

      def safe_resolve(name)
        @dependencies.resolve(name)
      rescue StandardError
        nil
      end

      def resolve_layout_metrics
        @dependencies.resolve(:layout_metrics)
      rescue StandardError
        nil
      end

      def set_message(text, duration = 2)
        notifier = @dependencies.resolve(:notification_service)
        notifier.set_message(@state, text, duration)
      rescue StandardError
        @state.dispatch(Shoko::Application::Actions::UpdateMessageAction.new(text))
      end

      def cleanup_popup_state
        ui_controller = safe_resolve(:ui_controller)
        ui_controller&.cleanup_popup_state
      rescue StandardError
        # Best effort
      end
    end
  end
end
