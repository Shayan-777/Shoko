# frozen_string_literal: true

require 'fileutils'

module Shoko
  module Application::Controllers
    # Handles all dictionary-related functionality: lookups, panel/popup display, language pairs
    class DictionaryController
      COMMON_SETUP_LANGS = %w[en de fr es it pt ru zh ja ko ar hi tr pl uk cs nl].freeze
      LANGUAGE_LABELS = {
        'en' => 'English',
        'de' => 'German',
        'fr' => 'French',
        'es' => 'Spanish',
        'it' => 'Italian',
        'pt' => 'Portuguese',
        'ru' => 'Russian',
        'zh' => 'Chinese',
        'ja' => 'Japanese',
        'ko' => 'Korean',
        'ar' => 'Arabic',
        'hi' => 'Hindi',
        'tr' => 'Turkish',
        'pl' => 'Polish',
        'uk' => 'Ukrainian',
        'cs' => 'Czech',
        'nl' => 'Dutch',
      }.freeze

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
          # Just redraw, component handles scroll state
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
        handle_dictionary_key("\e[A") # Simulate up arrow
        :handled
      end

      def dictionary_scroll_down(_key = nil)
        handle_dictionary_key("\e[B") # Simulate down arrow
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

      def determine_dictionary_display_mode(terminal_width, terminal_height)
        min_terminal = dictionary_panel_min_terminal_width
        return :popup if terminal_width < min_terminal

        available_right = dictionary_available_right_space(terminal_width, terminal_height)
        min_width = dictionary_panel_min_width
        return :panel if available_right >= min_width

        :popup
      rescue StandardError => e
        @logger&.debug("DictionaryController.determine_dictionary_display_mode failed: #{e.message}")
        :popup
      end

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
        popup = ensure_setup_popup
        return unless popup&.respond_to?(:show_setup)

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

        popup.show_setup(
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
        popup = @reader_state.dictionary_popup
        popup ||= ui_component_factory&.dictionary_popup
        return nil unless popup

        panel = @reader_state.dictionary_panel
        panel&.hide
        @state_writer.update_reader(
          dictionary_panel: nil,
          dictionary_popup: popup,
          dictionary_visible: true,
          mode: :dictionary,
          popup_menu: nil
        )
        activate_dictionary_mode
        popup
      end

      def handle_setup_change(result)
        return unless @setup_session

        stage = result[:stage]&.to_sym
        value = result[:value].to_s
        case stage
        when :prompt_source
          @setup_session[:source_input] = value
          @setup_session[:source_suggestion_index] = 0
        when :prompt_target
          @setup_session[:target_input] = value
          @setup_session[:target_suggestion_index] = 0
        end

        update_setup_popup(stage: stage, status: '', status_level: nil, input_value: value)
      end

      def handle_setup_select(result)
        return unless @setup_session

        stage = result[:stage]&.to_sym
        return unless %i[prompt_source prompt_target].include?(stage)

        index = result[:index].to_i
        set_setup_suggestion_index(stage, index)
        update_setup_popup(stage: stage, redraw: true)
      end

      def handle_setup_apply_suggestion(result)
        return unless @setup_session

        stage = result[:stage]&.to_sym
        value = result[:value].to_s
        return unless %i[prompt_source prompt_target].include?(stage)

        case stage
        when :prompt_source
          @setup_session[:source_input] = value
        when :prompt_target
          @setup_session[:target_input] = value
        end
        update_setup_popup(stage: stage, input_value: value, status: '', status_level: nil)
      end

      def handle_setup_swap
        return unless @setup_session
        return unless @setup_session[:stage] == :prompt_target

        target_candidate = normalize_dictionary_language(@setup_session[:target_input])
        unless target_candidate
          setup_error('Cannot swap yet. Enter/select a valid target language first.', stage: :prompt_target)
          return
        end

        old_source = @setup_session[:source_lang]
        @setup_session[:source_lang] = target_candidate
        @setup_session[:source_input] = target_candidate
        remember_manual_source_for_current_book(target_candidate)

        @setup_session[:target_input] = old_source.to_s
        @setup_session[:target_lang] = nil
        @setup_session[:target_suggestion_index] = 0

        update_setup_popup(
          stage: :prompt_target,
          source_lang: target_candidate,
          target_lang: nil,
          input_value: @setup_session[:target_input],
          prompt: setup_prompt(:prompt_target, source_lang: target_candidate),
          status: 'Swapped source/target. Pick the new target language.',
          status_level: nil,
          progress: 0.0
        )
      end

      def handle_setup_submit(result)
        return unless @setup_session

        stage = result[:stage]&.to_sym
        value = result[:value].to_s
        case stage
        when :prompt_source
          submit_setup_source(value)
        when :prompt_target
          submit_setup_target(value)
        end
      end

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

      def download_pair_for_setup(source, target)
        unless @dictionary_catalog_service
          setup_error('Dictionary catalog unavailable.', stage: :prompt_target)
          return
        end

        update_setup_popup(
          stage: :downloading,
          source_lang: source,
          target_lang: target,
          prompt: '',
          input_value: '',
          status: "Looking for #{source}-#{target} dataset...",
          status_level: nil,
          progress: 0.0
        )

        remote_items = @dictionary_catalog_service.list_remote
        entry = find_catalog_entry(remote_items, source: source, target: target)
        unless entry
          setup_error("No dictionary dataset found for #{source}-#{target}.", stage: :prompt_target)
          return
        end

        name = entry[:name] || entry['name'] || "#{source}-#{target}.sqlite3"
        destination = dictionary_storage_path
        last_draw = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @dictionary_catalog_service.download(entry, destination) do |done, total|
          progress = total.to_i.positive? ? done.to_f / total : 0.0
          percent = total.to_i.positive? ? (progress * 100).round : nil
          message = percent ? "Downloading #{name}... #{percent}%" : "Downloading #{name}..."
          update_setup_popup(
            stage: :downloading,
            source_lang: source,
            target_lang: target,
            status: message,
            status_level: nil,
            progress: progress,
            redraw: false
          )
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          next if (now - last_draw) < 0.08 && progress < 1.0

          draw_dictionary_screen
          last_draw = now
        end

        update_setup_popup(
          stage: :downloading,
          source_lang: source,
          target_lang: target,
          status: "Installed #{name}",
          status_level: :success,
          progress: 1.0
        )
        complete_lookup_after_setup(source, target)
      rescue StandardError => e
        setup_error("Download failed: #{e.message}", stage: :prompt_target)
      end

      def find_catalog_entry(remote_items, source:, target:)
        Array(remote_items).find do |item|
          src = item[:source] || item['source']
          tgt = item[:target] || item['target']
          normalize_dictionary_language(src) == source &&
            normalize_dictionary_language(tgt) == target
        end
      end

      def update_setup_popup(stage: nil, source_lang: nil, target_lang: nil, input_value: nil, prompt: nil,
                             status: nil, status_level: nil, progress: nil,
                             suggestions: nil, suggestion_index: nil, redraw: true)
        popup = ensure_setup_popup
        return unless popup&.respond_to?(:update_setup)

        resolved_stage = (stage || @setup_session&.dig(:stage))&.to_sym
        resolved_source = source_lang.nil? ? @setup_session&.dig(:source_lang) : source_lang
        resolved_input = if input_value.nil?
                           case resolved_stage
                           when :prompt_source
                             @setup_session&.dig(:source_input)
                           when :prompt_target
                             @setup_session&.dig(:target_input)
                           end
                         else
                           input_value
                         end
        resolved_suggestions = suggestions
        resolved_suggestion_index = suggestion_index
        if %i[prompt_source prompt_target].include?(resolved_stage)
          resolved_suggestions ||= setup_suggestions_for(stage: resolved_stage, source_lang: resolved_source,
                                                         input_value: resolved_input)
          resolved_suggestion_index ||= setup_suggestion_index_for(resolved_stage, resolved_suggestions)
        end

        popup.update_setup(
          stage: stage,
          source_lang: source_lang,
          target_lang: target_lang,
          input_value: input_value,
          prompt: prompt,
          status: status,
          status_level: status_level,
          progress: progress,
          suggestions: resolved_suggestions,
          suggestion_index: resolved_suggestion_index
        )
        draw_dictionary_screen if redraw
      end

      def setup_error(message, stage:)
        source = @setup_session[:source_lang]
        target = @setup_session[:target_lang]
        input_value = stage == :prompt_source ? @setup_session[:source_input].to_s : @setup_session[:target_input].to_s
        update_setup_popup(
          stage: stage,
          source_lang: source,
          target_lang: target,
          input_value: input_value,
          prompt: setup_prompt(stage, source_lang: source),
          status: message,
          status_level: :error,
          progress: 0.0
        )
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

      def setup_suggestions_for(stage:, source_lang:, input_value:)
        codes = case stage.to_sym
                when :prompt_source
                  source_setup_candidate_codes
                when :prompt_target
                  target_setup_candidate_codes(source_lang)
                else
                  []
                end
        filtered = filter_setup_candidate_codes(codes, input_value)
        filtered.first(8).map { |code| { code: code, label: setup_language_label(code) } }
      rescue StandardError
        []
      end

      def source_setup_candidate_codes
        configured_source = @config_reader.dictionary_source_lang
        configured_source = nil if dictionary_auto_setting?(configured_source)
        normalize_code_list(
          [
            dictionary_book_metadata_language,
            remembered_manual_source_for_current_book,
            configured_source,
            @dictionary_service&.configured_source_lang,
          ] +
          dictionary_available_pairs(@dictionary_service).map { |pair| pair[:source] } +
          COMMON_SETUP_LANGS
        )
      end

      def target_setup_candidate_codes(source_lang)
        pairs = dictionary_available_pairs(@dictionary_service)
        source = normalize_dictionary_language(source_lang)
        for_source = pairs.select { |pair| pair[:source] == source }.map { |pair| pair[:target] }
        fallbacks = pairs.map { |pair| pair[:target] }

        normalize_code_list(
          [
            @config_reader.dictionary_target_lang,
            @dictionary_service&.configured_target_lang,
          ] +
          for_source +
          fallbacks +
          COMMON_SETUP_LANGS
        )
      end

      def filter_setup_candidate_codes(codes, input_value)
        text = input_value.to_s.strip.downcase
        norm = normalize_dictionary_language(text)
        base = codes
        return base if text.empty?

        matching = base.select do |code|
          label = setup_language_label(code).downcase
          code.start_with?(text) ||
            code.start_with?(norm.to_s) ||
            label.start_with?(text) ||
            label.include?(text)
        end
        matching = base if matching.empty?

        matching.sort_by do |code|
          label = setup_language_label(code).downcase
          rank = if code == norm || code == text
                   0
                 elsif code.start_with?(text) || code.start_with?(norm.to_s)
                   1
                 elsif label.start_with?(text)
                   2
                 else
                   3
                 end
          [rank, code]
        end
      end

      def setup_language_label(code)
        LANGUAGE_LABELS[code.to_s.downcase] || code.to_s.upcase
      end

      def normalize_code_list(values)
        Array(values).filter_map { |value| normalize_dictionary_language(value) }.uniq
      end

      def setup_suggestion_index_key(stage)
        stage.to_sym == :prompt_source ? :source_suggestion_index : :target_suggestion_index
      end

      def set_setup_suggestion_index(stage, index)
        return unless @setup_session

        key = setup_suggestion_index_key(stage)
        @setup_session[key] = index.to_i
      end

      def setup_suggestion_index_for(stage, suggestions)
        return 0 unless @setup_session

        key = setup_suggestion_index_key(stage)
        idx = @setup_session[key].to_i
        max = [Array(suggestions).length - 1, 0].max
        idx = 0 if idx.negative?
        idx = max if idx > max
        @setup_session[key] = idx
        idx
      end

      def persist_target_language(target)
        @state_writer.update_config(dictionary_target_lang: target)
      rescue StandardError
        nil
      end

      def dictionary_storage_path
        configured = @config_reader.dictionary_path.to_s.strip
        path = if configured.empty?
                 @dictionary_availability&.default_databases_path ||
                   File.join(Dir.home, '.config', 'shoko', 'dictionary')
               else
                 File.expand_path(configured)
               end
        FileUtils.mkdir_p(path)
        path
      rescue StandardError
        fallback = @dictionary_availability&.default_databases_path ||
                   File.join(Dir.home, '.config', 'shoko', 'dictionary')
        FileUtils.mkdir_p(fallback)
        fallback
      end

      def dictionary_book_metadata_language
        metadata = @document&.metadata
        return nil unless metadata.is_a?(Hash)

        value = metadata[:language] || metadata['language']
        raw = value.to_s.strip
        return nil if raw.empty?

        raw
      rescue StandardError
        nil
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
        path = if @reader_state.respond_to?(:book_path)
                 @reader_state.book_path
               elsif @document.respond_to?(:source_path)
                 @document.source_path
               end
        text = path.to_s.strip
        return nil if text.empty?

        text
      rescue StandardError
        nil
      end

      def draw_dictionary_screen
        @reader_controller&.draw_screen
      rescue StandardError
        nil
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

      def dictionary_available_right_space(terminal_width, terminal_height)
        sidebar_width = sidebar_width_for(terminal_width, terminal_height)
        main_width = terminal_width - sidebar_width
        return 0 if main_width <= 0

        layout_service = @layout_service
        view_mode = @config_reader.view_mode || :single
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
        return 0 unless @sidebar_state.sidebar_visible?

        sidebar_bounds = @reader_controller&.render_coordinator&.sidebar_bounds(terminal_width, terminal_height)
        return sidebar_bounds.width if sidebar_bounds&.width

        0
      rescue StandardError => e
        @logger&.debug("DictionaryController.sidebar_width_for failed: #{e.message}")
        0
      end

      def resolve_dictionary_pair(dictionary_service)
        source_setting = @config_reader.dictionary_source_lang
        target_setting = @config_reader.dictionary_target_lang

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
        @document&.language
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
                              candidate_targets.min
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

        code = raw.downcase.tr(' ', '_').split(/[-_]/).first.to_s
        map = {
          'english' => 'en',
          'eng' => 'en',
          'german' => 'de',
          'deutsch' => 'de',
          'deu' => 'de',
          'ger' => 'de',
          'french' => 'fr',
          'fra' => 'fr',
          'fre' => 'fr',
          'spanish' => 'es',
          'espanol' => 'es',
          'spa' => 'es',
          'italian' => 'it',
          'ita' => 'it',
          'portuguese' => 'pt',
          'por' => 'pt',
          'dutch' => 'nl',
          'nld' => 'nl',
          'dut' => 'nl',
          'polish' => 'pl',
          'pol' => 'pl',
          'czech' => 'cs',
          'cze' => 'cs',
          'ces' => 'cs',
          'ukrainian' => 'uk',
          'ukr' => 'uk',
          'turkish' => 'tr',
          'tur' => 'tr',
          'arabic' => 'ar',
          'ara' => 'ar',
          'hindi' => 'hi',
          'hin' => 'hi',
          'japanese' => 'ja',
          'jpn' => 'ja',
          'korean' => 'ko',
          'kor' => 'ko',
          'rus' => 'ru',
          'russian' => 'ru',
          'zho' => 'zh',
          'chi' => 'zh',
          'chinese' => 'zh',
          'mandarin' => 'zh',
        }
        mapped = map[code]
        return mapped if mapped

        return code if code.match?(/\A[a-z]{2,3}\z/)

        nil
      end

      def extract_selected_text_from_selection(selection_range)
        return nil unless @selection_service && @rendered_content_reader

        if @selection_service.respond_to?(:extract_from_state)
          @selection_service.extract_from_state(@reader_state, rendered_content_reader: @rendered_content_reader,
                                                               selection_range: selection_range)
        else
          rendered_lines = @rendered_content_reader.rendered_lines
          @selection_service.extract_text(selection_range, rendered_lines)
        end
      end

      def set_message(text, duration = 2)
        if @notification_service
          @notification_service.set_message(nil, text, duration)
        else
          @state_writer.update_reader(message: text)
        end
      rescue StandardError
        @state_writer.update_reader(message: text)
      end

      def cleanup_popup_state
        @ui_controller&.cleanup_popup_state
      rescue StandardError
        # Best effort
      end
    end
  end
end
