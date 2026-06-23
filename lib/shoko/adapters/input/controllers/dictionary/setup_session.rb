# frozen_string_literal: true

require 'shoko/shared/errors'
require_relative 'constants'
require_relative '../support/session_outcome_helpers'
require_relative '../support/message_notifier'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dictionary
          # The dictionary install wizard: a self-contained collaborator that
          # owns the multi-stage setup session (`prompt_source -> prompt_target
          # -> downloading`) and the language-pair/suggestion logic feeding it.
          #
          # Previously this lived as two include-once mixins
          # (SetupFlowSupport + LanguagePairSupport) bound to DictionaryController
          # through shared ivars; it is now a real object that holds its own
          # state (`@setup_session`, the per-book manual-source memory) and
          # receives every dependency explicitly. DictionaryController drives it
          # through a small public surface and never reaches into its internals.
          class SetupSession
            include Shoko::Adapters::Input::Controllers::Support::SessionOutcomeHelpers
            include Shoko::Adapters::Input::Controllers::Support::MessageNotifier

            # Built from DictionaryController's own typed dependency bundle so the
            # wizard shares exactly the controller's wiring (and stays within the
            # constructor-arity budget instead of taking a dozen flat params).
            def initialize(dependencies:)
              assign_service_dependencies(dependencies.services)
              assign_state_dependencies(dependencies.state)
              assign_controller_dependencies(dependencies.controllers)
              @dictionary_ui_session = dependencies.ui.dictionary_ui_session
              @manual_source_lang_by_book = {}
              @setup_session = nil
            end

            # ---- Public surface used by DictionaryController ----

            # Look the query up immediately when a usable pair exists, otherwise
            # open the install wizard.
            def begin_lookup(query:)
              begin_lookup_with_setup(query: query)
            end

            # Publish a lookup result to the definition card and leave setup.
            def present_result(result, announce: true)
              show_dictionary_lookup(result, announce: announce)
            end

            # The configured/derived source+target pair for the current book.
            def resolve_pair
              resolve_dictionary_pair(@dictionary_service)
            end

            def handle_change(result) = handle_setup_change(result)
            def handle_select(result) = handle_setup_select(result)
            def handle_apply_suggestion(result) = handle_setup_apply_suggestion(result)
            def handle_swap = handle_setup_swap
            def handle_submit(result) = handle_setup_submit(result)

            # Forget the in-flight wizard (the per-book manual-source memory is
            # retained for the session's lifetime).
            def clear
              @setup_session = nil
            end

            private

            def assign_service_dependencies(services)
              @dictionary_service = services.dictionary_service
              @dictionary_catalog_service = services.dictionary_catalog_service
              @dictionary_storage = services.dictionary_storage
              @notification_service = services.notification_service
            end

            def assign_state_dependencies(state)
              @config_reader = state.config_reader
              @reader_session_mutator = state.reader_session_mutator
              @document = state.document
              @reader_state = state.reader_state
            end

            def assign_controller_dependencies(controllers)
              @reader_controller = controllers.reader_controller
              @input_controller = controllers.input_controller
              @clock = controllers.clock
            end

            # ===== setup flow =====

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
              announce = result.search_mode != :unavailable
              show_dictionary_lookup(result, announce: announce)
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

              target_candidate = swappable_target_candidate
              return unless target_candidate

              old_source = @setup_session[:source_lang]
              @setup_session[:source_lang] = target_candidate
              @setup_session[:source_input] = target_candidate
              remember_manual_source_for_current_book(target_candidate)

              @setup_session[:target_input] = old_source.to_s
              @setup_session[:target_lang] = nil
              @setup_session[:target_suggestion_index] = 0

              show_swapped_target_prompt(target_candidate)
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

            def swappable_target_candidate
              target_candidate = normalize_dictionary_language(@setup_session[:target_input])
              return target_candidate if target_candidate

              setup_error('Cannot swap yet. Enter/select a valid target language first.', stage: :prompt_target)
              nil
            end

            def show_swapped_target_prompt(target_candidate)
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

            def submit_setup_source(raw_value)
              source = validated_setup_language(
                :prompt_source,
                raw_value,
                'Please enter a valid source language (for example: en, de, fr).'
              )
              return unless source

              store_setup_source(source)
              transition_setup_to_target_prompt(source)
            end

            def submit_setup_target(raw_value)
              target = validated_setup_language(
                :prompt_target,
                raw_value,
                'Please enter a valid target language (for example: en, de, fr).'
              )
              source = current_setup_source
              return unless target && source

              finalize_setup_target(source, target)
            end

            def complete_lookup_after_setup(source, target)
              query = @setup_session[:query].to_s
              result = @dictionary_service.lookup(query, source_lang: source, target_lang: target)
              pair_info = { source: source, target: target, fallback: false, available: true, available_pairs: [] }
              present_lookup_result(result, pair_info: pair_info)
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

              suggestions = setup_suggestions_for(stage: stage,
                                                  source_lang: @setup_session[:source_lang],
                                                  input_value: text)
              index = setup_suggestion_index_for(stage, suggestions)
              suggestions[index]&.dig(:code).to_s
            end

            def persist_target_language(target)
              @reader_session_mutator.update_config(dictionary_target_lang: target)
            end

            def validated_setup_language(stage, raw_value, error_message)
              value = effective_setup_submit_value(stage, raw_value)
              language = normalize_dictionary_language(value)
              return language if language

              setup_error(error_message, stage: stage)
              nil
            end

            def store_setup_source(source)
              @setup_session[:source_lang] = source
              @setup_session[:source_input] = source
              remember_manual_source_for_current_book(source)
            end

            def transition_setup_to_target_prompt(source)
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

            def current_setup_source
              source = @setup_session[:source_lang]
              return source if source

              setup_error('Source language is required.', stage: :prompt_source)
              nil
            end

            def finalize_setup_target(source, target)
              @setup_session[:target_lang] = target
              @setup_session[:target_input] = target
              persist_target_language(target)

              if @dictionary_service.language_pair_available?(source, target)
                complete_lookup_after_setup(source, target)
              else
                download_pair_for_setup(source, target)
              end
            end

            def download_pair_for_setup(source, target)
              return unless catalog_available_for_setup?

              show_download_lookup_status(source, target)
              entry = catalog_entry_for_setup(source, target)
              return unless entry

              name = catalog_entry_name(entry, source, target)
              download_catalog_entry(entry, name, source, target)
              finalize_download_setup(name, source, target)
            rescue Shoko::Error => e
              setup_error("Download failed: #{e.message}", stage: :prompt_target)
            end

            def find_catalog_entry(remote_items, source:, target:)
              Array(remote_items).find do |item|
                src = item[:source]
                tgt = item[:target]
                normalize_dictionary_language(src) == source &&
                  normalize_dictionary_language(tgt) == target
              end
            end

            def dictionary_storage_path
              @dictionary_storage&.ensure_databases_path(@config_reader.dictionary_path)
            end

            def monotonic_now
              @clock.monotonic_now
            end

            def catalog_available_for_setup?
              return true if @dictionary_catalog_service

              setup_error('Dictionary catalog unavailable.', stage: :prompt_target)
              false
            end

            def show_download_lookup_status(source, target)
              update_download_setup_popup(
                source: source,
                target: target,
                status: "Looking for #{source}-#{target} dataset...",
                progress: 0.0,
                prompt: '',
                input_value: ''
              )
            end

            def catalog_entry_for_setup(source, target)
              remote_items = @dictionary_catalog_service.list_remote
              entry = find_catalog_entry(remote_items, source: source, target: target)
              return entry if entry

              setup_error("No dictionary dataset found for #{source}-#{target}.", stage: :prompt_target)
              nil
            end

            def catalog_entry_name(entry, source, target)
              entry[:name] || "#{source}-#{target}.sqlite3"
            end

            def download_catalog_entry(entry, name, source, target)
              last_draw = monotonic_now
              @dictionary_catalog_service.download(entry, dictionary_storage_path) do |done, total|
                progress, message = download_progress(done, total, name)
                update_download_setup_popup(
                  source: source,
                  target: target,
                  status: message,
                  progress: progress,
                  redraw: false
                )
                last_draw = redraw_download_screen(progress, last_draw)
              end
            end

            def download_progress(done, total, name)
              progress = total.to_i.positive? ? done.to_f / total : 0.0
              percent = total.to_i.positive? ? (progress * 100).round : nil
              message = percent ? "Downloading #{name}... #{percent}%" : "Downloading #{name}..."
              [progress, message]
            end

            def redraw_download_screen(progress, last_draw)
              now = monotonic_now
              return last_draw if (now - last_draw) < 0.08 && progress < 1.0

              draw_dictionary_screen
              now
            end

            def finalize_download_setup(name, source, target)
              update_download_setup_popup(
                source: source,
                target: target,
                status: "Installed #{name}",
                status_level: :success,
                progress: 1.0
              )
              complete_lookup_after_setup(source, target)
            end

            def update_download_setup_popup(source:, target:, status:, progress:, status_level: nil,
                                            redraw: true, prompt: nil, input_value: nil)
              update_setup_popup(
                stage: :downloading,
                source_lang: source,
                target_lang: target,
                prompt: prompt,
                input_value: input_value,
                status: status,
                status_level: status_level,
                progress: progress,
                redraw: redraw
              )
            end

            def update_setup_popup(stage: nil, source_lang: nil, target_lang: nil, input_value: nil, prompt: nil,
                                   status: nil, status_level: nil, progress: nil,
                                   suggestions: nil, suggestion_index: nil, redraw: true)
              return unless setup_popup_ready?

              outcome = update_setup_session(
                stage: stage,
                source_lang: source_lang,
                target_lang: target_lang,
                input_value: input_value,
                prompt: prompt,
                status: status,
                status_level: status_level,
                progress: progress,
                suggestions: suggestions,
                suggestion_index: suggestion_index
              )
              return unless session_ok?(outcome)

              draw_dictionary_screen if redraw
            end

            def setup_error(message, stage:)
              source = @setup_session[:source_lang]
              target = @setup_session[:target_lang]
              update_setup_popup(
                stage: stage,
                source_lang: source,
                target_lang: target,
                input_value: setup_error_input_value(stage),
                prompt: setup_prompt(stage, source_lang: source),
                status: message,
                status_level: :error,
                progress: 0.0
              )
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

            def setup_popup_payload(**attributes)
              resolved_stage, resolved_source, resolved_input = resolve_setup_popup_state(
                attributes[:stage],
                attributes[:source_lang],
                attributes[:input_value]
              )
              resolved_suggestions, resolved_suggestion_index = resolve_setup_suggestions(
                stage: resolved_stage,
                source_lang: resolved_source,
                input_value: resolved_input,
                suggestions: attributes[:suggestions],
                suggestion_index: attributes[:suggestion_index]
              )
              build_setup_popup_payload(attributes, resolved_suggestions, resolved_suggestion_index)
            end

            def update_setup_session(**)
              @dictionary_ui_session.update_setup(**setup_popup_payload(**))
            end

            def build_setup_popup_payload(attributes, suggestions, suggestion_index)
              attributes.merge(suggestions: suggestions, suggestion_index: suggestion_index)
            end

            def resolve_setup_popup_state(stage, source_lang, input_value)
              resolved_stage = (stage || @setup_session&.dig(:stage))&.to_sym
              resolved_source = source_lang.nil? ? @setup_session&.dig(:source_lang) : source_lang
              [resolved_stage, resolved_source, resolve_setup_input_value(resolved_stage, input_value)]
            end

            def resolve_setup_input_value(stage, input_value)
              return input_value unless input_value.nil?

              case stage
              when :prompt_source
                @setup_session&.dig(:source_input)
              when :prompt_target
                @setup_session&.dig(:target_input)
              end
            end

            def resolve_setup_suggestions(stage:, source_lang:, input_value:, suggestions:, suggestion_index:)
              return [suggestions, suggestion_index] unless %i[prompt_source prompt_target].include?(stage)

              resolved_suggestions = suggestions || setup_suggestions_for(
                stage: stage,
                source_lang: source_lang,
                input_value: input_value
              )
              resolved_index = suggestion_index || setup_suggestion_index_for(stage, resolved_suggestions)
              [resolved_suggestions, resolved_index]
            end

            def setup_error_input_value(stage)
              return @setup_session[:source_input].to_s if stage == :prompt_source

              @setup_session[:target_input].to_s
            end

            # ===== language normalization, pair selection, suggestions =====

            def resolve_dictionary_pair(dictionary_service)
              available_pairs = dictionary_available_pairs(dictionary_service)
              selected = select_dictionary_pair(
                resolved_dictionary_source(dictionary_service),
                resolved_dictionary_target(dictionary_service),
                available_pairs
              )
              selected[:available_pairs] = available_pairs
              selected
            end

            def dictionary_auto_setting?(value)
              return true if value.nil?

              str = value.to_s.strip
              str.empty? || str.casecmp('auto').zero?
            end

            def dictionary_available_pairs(dictionary_service)
              pairs = dictionary_service.available_language_pairs
              Array(pairs).filter_map do |pair|
                normalized = normalize_pair_hash(pair)
                source = normalized[:source]
                target = normalized[:target]
                next if source.nil? || target.nil?

                {
                  source: normalize_dictionary_language(source),
                  target: normalize_dictionary_language(target),
                }
              end.uniq
            end

            def select_dictionary_pair(source, target, pairs)
              exact_dictionary_pair(source, target, pairs) ||
                source_fallback_dictionary_pair(source, target, pairs) ||
                unavailable_dictionary_pair(source, target)
            end

            def normalize_dictionary_language(value)
              return nil if value.nil?

              raw = value.to_s.strip
              return nil if raw.empty?

              code = raw.downcase.tr(' ', '_').split(/[-_]/).first.to_s
              mapped = Dictionary::Constants::LANGUAGE_CODE_MAP[code]
              return mapped if mapped

              return code if code.match?(/\A[a-z]{2,3}\z/)

              nil
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
            end

            def normalize_pair_hash(pair)
              unless pair.is_a?(Hash)
                raise Shoko::MalformedDictionaryInputError, "language pair must be Hash, got #{pair.class}"
              end

              pair.each_with_object({}) do |(key, value), acc|
                normalized_key = key.is_a?(String) ? key.to_sym : key
                acc[normalized_key] = value
              end
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
                Dictionary::Constants::COMMON_SETUP_LANGS
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
                Dictionary::Constants::COMMON_SETUP_LANGS
              )
            end

            def filter_setup_candidate_codes(codes, input_value)
              text, normalized = normalized_setup_filter(input_value)
              return codes if text.empty?

              matching = codes.select { |code| setup_candidate_matches?(code, text, normalized) }
              ranked_setup_candidate_codes(matching.empty? ? codes : matching, text, normalized)
            end

            def setup_language_label(code)
              Dictionary::Constants::LANGUAGE_LABELS[code.to_s.downcase] || code.to_s.upcase
            end

            def normalize_code_list(values)
              Array(values).filter_map { |value| normalize_dictionary_language(value) }.uniq
            end

            def resolved_dictionary_source(dictionary_service)
              value = dictionary_configured_source_value
              normalize_dictionary_language(value) || dictionary_service.configured_source_lang
            end

            def resolved_dictionary_target(dictionary_service)
              value = dictionary_configured_target_value
              normalize_dictionary_language(value) || dictionary_service.configured_target_lang
            end

            def dictionary_configured_source_value
              source_setting = @config_reader.dictionary_source_lang
              dictionary_auto_setting?(source_setting) ? dictionary_book_language : source_setting
            end

            def dictionary_configured_target_value
              target_setting = @config_reader.dictionary_target_lang
              dictionary_auto_setting?(target_setting) ? nil : target_setting
            end

            def exact_dictionary_pair(source, target, pairs)
              return unless source && target
              return unless pairs.any? { |pair| pair[:source] == source && pair[:target] == target }

              available_dictionary_pair(source, target, fallback: false)
            end

            def source_fallback_dictionary_pair(source, target, pairs)
              return unless source

              source_pairs = pairs.select { |pair| pair[:source] == source }
              return if source_pairs.empty?

              chosen_target = choose_dictionary_target(target, source_pairs)
              available_dictionary_pair(source, chosen_target, fallback: chosen_target != target)
            end

            def choose_dictionary_target(target, source_pairs)
              candidate_targets = source_pairs.map { |pair| pair[:target] }
              return target if target && candidate_targets.include?(target)

              candidate_targets.min
            end

            def available_dictionary_pair(source, target, fallback:)
              { source: source, target: target, available: true, fallback: fallback }
            end

            def unavailable_dictionary_pair(source, target)
              { source: source, target: target, available: false, fallback: false }
            end

            def normalized_setup_filter(input_value)
              text = input_value.to_s.strip.downcase
              [text, normalize_dictionary_language(text).to_s]
            end

            def setup_candidate_matches?(code, text, normalized)
              label = setup_language_label(code).downcase
              code.start_with?(text, normalized) ||
                label.start_with?(text) ||
                label.include?(text)
            end

            def ranked_setup_candidate_codes(codes, text, normalized)
              codes.sort_by { |code| [setup_candidate_rank(code, text, normalized), code] }
            end

            def setup_candidate_rank(code, text, normalized)
              label = setup_language_label(code).downcase
              return 0 if code == normalized || code == text
              return 1 if code.start_with?(text, normalized)
              return 2 if label.start_with?(text)

              3
            end

            # ===== book context + UI hooks (owned by the wizard) =====

            def show_dictionary_lookup(result, announce: true)
              outcome = @dictionary_ui_session&.apply_result(result)
              return unless session_ok?(outcome)

              @setup_session = nil
              activate_dictionary_mode
              set_message("Looking up '#{result.query}'", 2) if announce
            end

            def draw_dictionary_screen
              @reader_controller&.draw_screen
            end

            def activate_dictionary_mode
              @input_controller&.enter_modal_mode(:dictionary)
            end

            def dictionary_book_metadata_language
              metadata = @document&.metadata
              return nil unless metadata.is_a?(Hash)

              value = metadata[:language]
              raw = value.to_s.strip
              return nil if raw.empty?

              raw
            end

            def dictionary_book_language
              @document&.language
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
          end
        end
      end
    end
  end
end
