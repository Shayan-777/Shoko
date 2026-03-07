# frozen_string_literal: true

require_relative 'dictionary/constants'
require_relative 'support/message_notifier'
require_relative '../../../shared/type_coercion'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Handles all annotation overlay functionality: annotations overlay and annotation editor
        class AnnotationOverlayController
          include Shoko::Adapters::Input::Controllers::Support::MessageNotifier

          # Raised when required dependencies are missing for an annotation action.
          class MissingDependencyError < StandardError; end
          StateDependencies = Data.define(:reader_state, :state_writer, :state_controller)
          ServiceDependencies = Data.define(:annotation_service, :dictionary_service)
          InputDependencies = Data.define(:input_controller, :annotation_overlay_ui_session)
          NotificationDependencies = Data.define(:notification_service, :logger)
          Dependencies = Data.define(:state, :services, :input, :notifications) do
            def self.build(reader_state:, state_writer:, state_controller: nil,
                           annotation_service: nil, dictionary_service: nil,
                           input_controller: nil, annotation_overlay_ui_session: nil,
                           notification_service:, logger: nil)
              new(
                state: StateDependencies.new(
                  reader_state: reader_state,
                  state_writer: state_writer,
                  state_controller: state_controller
                ),
                services: ServiceDependencies.new(
                  annotation_service: annotation_service,
                  dictionary_service: dictionary_service
                ),
                input: InputDependencies.new(
                  input_controller: input_controller,
                  annotation_overlay_ui_session: annotation_overlay_ui_session
                ),
                notifications: NotificationDependencies.new(
                  notification_service: notification_service,
                  logger: logger
                )
              )
            end

            def validate!
              raise ArgumentError, 'notification_service is required' if notifications.notification_service.nil?

              self
            end
          end

          BOUNDARY_ERRORS = [MissingDependencyError, ArgumentError, TypeError, RuntimeError].freeze
          SPELL_SUGGESTION_LIMIT = 5
          SPELL_SUGGESTION_FETCH_LIMIT = 15

          def initialize(deps:)
            dependencies = deps.validate!
            @reader_state = dependencies.state.reader_state
            @state_writer = dependencies.state.state_writer
            @state_controller = dependencies.state.state_controller
            @annotation_service = dependencies.services.annotation_service
            @dictionary_service = dependencies.services.dictionary_service
            @input_controller = dependencies.input.input_controller
            @annotation_overlay_ui_session = dependencies.input.annotation_overlay_ui_session
            @notification_service = dependencies.notifications.notification_service
            @logger = dependencies.notifications.logger
          end

          def open_annotations
            @annotation_overlay_ui_session&.toggle_annotations
          end

          def open_annotation_editor_overlay(text:, range:, chapter_index:, annotation: nil)
            show_annotation_editor_overlay(text: text,
                                           range: range,
                                           chapter_index: chapter_index,
                                           annotation: annotation)
          end

          def show_annotations_overlay
            unless @annotation_overlay_ui_session
              raise MissingDependencyError, 'Dependency :annotation_overlay_ui_session not available'
            end

            outcome = @annotation_overlay_ui_session.open_annotations
            return unless session_ok?(outcome)

            set_message('Annotations overlay open (up/down navigate, Enter open, e edit, d delete)', 3)
          rescue *BOUNDARY_ERRORS => e
            @logger&.debug("AnnotationOverlayController.show_annotations_overlay failed: #{e.message}")
            cleanup_annotations_overlay_fallback
          end

          def close_annotations_overlay
            @annotation_overlay_ui_session&.close_annotations
          rescue *BOUNDARY_ERRORS => e
            @logger&.debug("AnnotationOverlayController.close_annotations_overlay failed: #{e.message}")
            cleanup_annotations_overlay_fallback
          end

          def show_annotation_editor_overlay(text:, range:, chapter_index:, annotation: nil)
            message = 'Annotation editor unavailable'
            unless @annotation_overlay_ui_session
              raise MissingDependencyError, 'Dependency :annotation_overlay_ui_session not available'
            end

            open_outcome = @annotation_overlay_ui_session.open_editor(text: text, range: range, chapter_index: chapter_index,
                                                                      annotation: annotation)
            if session_ok?(open_outcome) && activate_annotation_editor_overlay_session
              message = 'Annotation editor active (Ctrl+S save, Esc cancel)'
            else
              cleanup_annotation_editor_overlay_fallback
            end
          rescue *BOUNDARY_ERRORS => e
            cleanup_annotation_editor_overlay_fallback
            log_dependency_error(:show_annotation_editor_overlay, e)
          ensure
            set_message(message, 3)
          end

          def close_annotation_editor_overlay
            @annotation_overlay_ui_session&.close_editor
            deactivate_annotation_editor_overlay_session
          rescue *BOUNDARY_ERRORS => e
            @logger&.debug("AnnotationOverlayController.close_annotation_editor_overlay failed: #{e.message}")
            cleanup_annotation_editor_overlay_fallback
          end

          def open_annotation_from_overlay(annotation)
            with_normalized_annotation(annotation) do |normalized|
              @state_controller&.jump_to_annotation(normalized)
              close_annotations_overlay
            end
          rescue *BOUNDARY_ERRORS => e
            @logger&.debug("AnnotationOverlayController.open_annotation_from_overlay failed: #{e.message}")
            close_annotations_overlay
          end

          def edit_annotation_from_overlay(annotation)
            with_normalized_annotation(annotation) do |normalized|
              close_annotations_overlay
              show_annotation_editor_overlay(text: normalized[:text],
                                             range: normalized[:range],
                                             chapter_index: normalized[:chapter_index],
                                             annotation: normalized)
            end
          end

          def delete_annotation_from_overlay(annotation)
            with_normalized_annotation(annotation) do |normalized|
              new_index = @state_controller&.delete_annotation_by_id(normalized)

              @annotation_overlay_ui_session&.set_annotations_selected_index(new_index) unless new_index.nil?

              annotations = @reader_state.annotations || []
              close_annotations_overlay if annotations.empty?
              set_message('Annotation deleted', 2)
            end
          rescue *BOUNDARY_ERRORS => e
            @logger&.debug("AnnotationOverlayController.delete_annotation_from_overlay failed: #{e.message}")
            close_annotations_overlay
          end

          def handle_annotation_editor_overlay_event(result)
            result = session_payload(result)
            return unless result.is_a?(Hash)

            type = result[:type] || result['type']
            case type
            when :save
              save_annotation_from_overlay(result[:note])
            when :cancel
              cancel_annotation_editor_overlay
            end
          end

          def annotations_up
            process_annotations_overlay_event(session_payload(@annotation_overlay_ui_session&.annotations_up))
          end

          def annotations_down
            process_annotations_overlay_event(session_payload(@annotation_overlay_ui_session&.annotations_down))
          end

          def annotations_open
            process_annotations_overlay_event(session_payload(@annotation_overlay_ui_session&.annotations_open))
          end

          def annotations_edit
            process_annotations_overlay_event(session_payload(@annotation_overlay_ui_session&.annotations_edit))
          end

          def annotations_delete
            process_annotations_overlay_event(session_payload(@annotation_overlay_ui_session&.annotations_delete))
          end

          def annotations_cancel
            process_annotations_overlay_event(session_payload(@annotation_overlay_ui_session&.annotations_cancel))
          end

          def annotation_editor_insert_char(char)
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_insert_char(char)))
          end

          def annotation_editor_backspace
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_backspace))
          end

          def annotation_editor_enter
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_enter))
          end

          def annotation_editor_move_left
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_move_left))
          end

          def annotation_editor_move_right
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_move_right))
          end

          def annotation_editor_move_up
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_move_up))
          end

          def annotation_editor_move_down
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_move_down))
          end

          def annotation_editor_cancel
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_cancel))
          end

          def annotation_editor_save
            process_annotation_editor_event(session_payload(@annotation_overlay_ui_session&.editor_save))
          end

          def annotation_editor_spellcheck
            target = session_payload(@annotation_overlay_ui_session&.editor_spellcheck_target)
            word = spellcheck_word(target)

            unless word
              @annotation_overlay_ui_session&.editor_show_spell_suggestions(target: nil, suggestions: [])
              set_message('Place the cursor on a word to spell-check', 2)
              return :handled
            end

            unless @dictionary_service&.available?
              @annotation_overlay_ui_session&.editor_show_spell_suggestions(target: target, suggestions: [])
              set_message('Dictionary datasets unavailable for spell suggestions', 3)
              return :handled
            end

            scopes = spell_lookup_scopes
            if scopes.empty?
              @annotation_overlay_ui_session&.editor_show_spell_suggestions(target: target, suggestions: [])
              set_message('No healthy dictionary datasets available for spell suggestions', 3)
              return :handled
            end

            lookup = resolve_spell_lookup(word, target, scopes)
            scope = lookup[:scope]
            suggestions = lookup[:suggestions]
            @annotation_overlay_ui_session&.editor_show_spell_suggestions(
              target: target,
              suggestions: suggestions,
              scope_key: scope[:key],
              scope_label: scope[:label],
              can_cycle: scopes.length > 1
            )

            if suggestions.empty?
              set_message("No #{scope[:label]} suggestions for '#{word}'", 2)
            else
              set_message("Spelling suggestions for '#{word}' (#{scope[:label]})", 2)
            end

            :handled
          rescue *BOUNDARY_ERRORS => e
            @logger&.debug("AnnotationOverlayController.annotation_editor_spellcheck failed: #{e.message}")
            set_message('Spell suggestions unavailable', 2)
            :handled
          end

          def handle_annotation_editor_overlay_click(col, row)
            session_payload(@annotation_overlay_ui_session&.handle_editor_click(col, row))
          end

          def annotations_overlay_visible?
            @annotation_overlay_ui_session&.annotations_visible? == true
          end

          def annotation_editor_visible?
            @annotation_overlay_ui_session&.annotation_editor_visible? == true
          end

          def refresh_theme(theme_context:)
            color_mode = theme_context&.color_mode
            @annotation_overlay_ui_session&.refresh_theme(color_mode: color_mode)
          end

          # Refresh annotations from persistence into state
          def refresh_annotations
            @state_controller&.refresh_annotations
          rescue *BOUNDARY_ERRORS => e
            @logger&.debug("AnnotationOverlayController.refresh_annotations failed: #{e.message}")
          end

          # Provide current book path for modes/components that need persistence context
          def current_book_path
            @reader_state.book_path
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
            result.is_a?(Shoko::Shared::Contracts::SessionOutcome)
          end

          def process_annotations_overlay_event(result)
            return :pass unless result
            return :pass unless result.is_a?(Hash)

            case result[:type] || result['type']
            when :selection_change
              index = result[:index]
              @state_writer&.update_sidebar(
                annotations_selected: index,
                sidebar_annotations_selected: index
              )
              :handled
            when :open
              open_annotation_from_overlay(result[:annotation])
              :handled
            when :edit
              edit_annotation_from_overlay(result[:annotation])
              :handled
            when :delete
              delete_annotation_from_overlay(result[:annotation])
              :handled
            when :close
              close_annotations_overlay
              :handled
            else
              :pass
            end
          end

          def process_annotation_editor_event(result)
            payload = session_payload(result)
            return :handled if payload.nil?
            return :handled unless payload.is_a?(Hash)

            handle_annotation_editor_overlay_event(payload)
            :handled
          end

          def save_annotation_from_overlay(note)
            svc = @annotation_service
            path = current_book_path
            context = @annotation_overlay_ui_session&.editor_context
            unless svc && path && context
              cancel_annotation_editor_overlay
              return
            end

            begin
              if context && context[:annotation_id]
                svc.update(path, context[:annotation_id], note)
                set_message('Annotation updated', 2)
              else
                svc.add(path, context[:selected_text], note, context[:selection_range], context[:chapter_index], nil)
                set_message('Annotation saved!', 2)
              end
              refresh_annotations
            rescue *BOUNDARY_ERRORS => e
              set_message("Save failed: #{e.message}", 3)
            ensure
              close_annotation_editor_overlay
              @state_writer.clear_selection
            end
          end

          def cancel_annotation_editor_overlay
            close_annotation_editor_overlay
            set_message('Annotation cancelled', 2)
            @state_writer.clear_selection
          end

          def activate_annotation_editor_overlay_session
            raise MissingDependencyError, 'Dependency :input_controller not available' unless @input_controller

            @input_controller.enter_modal_mode(:annotation_editor)
            true
          rescue MissingDependencyError => e
            log_dependency_error(:activate_annotation_editor_overlay_session, e)
            false
          end

          def deactivate_annotation_editor_overlay_session
            @input_controller&.exit_modal_mode(:annotation_editor)
          end

          def cleanup_annotations_overlay_fallback
            @annotation_overlay_ui_session&.close_annotations || @state_writer.update_reader(annotations_overlay: nil)
          rescue *BOUNDARY_ERRORS => e
            @logger&.debug("AnnotationOverlayController.cleanup_annotations_overlay_fallback failed: #{e.message}")
            nil
          end

          def cleanup_annotation_editor_overlay_fallback
            @annotation_overlay_ui_session&.close_editor || @state_writer.update_reader(annotation_editor_overlay: nil)
            deactivate_annotation_editor_overlay_session
          end

          def normalize_annotation(annotation)
            return nil unless annotation.is_a?(Hash)

            annotation.transform_keys do |key|
              key.is_a?(String) ? key.to_sym : key
            end
          end

          def with_normalized_annotation(annotation)
            normalized = normalize_annotation(annotation)
            return unless normalized

            yield normalized
          end

          def log_dependency_error(context, error)
            @logger&.error('Annotation editor activation failed', context: context, error: error.message)
          end

          def spellcheck_word(target)
            return nil unless target.is_a?(Hash)

            word = target[:word] || target['word']
            normalized = word.to_s.strip
            normalized.empty? ? nil : normalized
          end

          def spell_suggestions_for(word)
            spell_suggestions_for_scope(word, spell_lookup_scopes.first)
          end

          def spell_suggestions_for_scope(word, scope)
            spell_suggestions_from_matches(spell_ranked_matches_for_scope(word, scope))
          end

          def spell_ranked_matches_for_scope(word, scope)
            return [] unless scope.is_a?(Hash)

            Array(scope[:strategies]).each_with_index.each_with_object([]) do |(strategy, strategy_index), matches|
              fetch_spell_matches(word, strategy).each do |match|
                candidate = match.word.to_s.strip
                next if candidate.empty?
                next if candidate.casecmp(word).zero?

                matches << {
                  word: candidate,
                  similarity: match.similarity.to_f,
                  strategy_index: strategy_index,
                  mode_rank: strategy[:mode] == :source ? 0 : 1,
                }
              end
            end
                                               .sort_by do |match|
              [-match[:similarity], match[:mode_rank], match[:strategy_index], match[:word].length, match[:word].downcase]
            end
          end

          def spell_suggestions_from_matches(matches)
            Array(matches)
              .each_with_object([]) do |match, suggestions|
                next if suggestions.any? { |existing| existing.casecmp(match[:word]).zero? }

                suggestions << match[:word]
                break suggestions if suggestions.length >= SPELL_SUGGESTION_LIMIT
              end
          end

          def resolve_spell_lookup(word, target, scopes)
            state = session_payload(@annotation_overlay_ui_session&.editor_spell_suggestions_state)
            return best_spell_lookup(word, scopes) unless same_spell_target?(state, target)

            current_key = state[:scope_key] || state['scope_key']
            current_index = scopes.index { |scope| scope[:key] == current_key }
            next_index = current_index ? (current_index + 1) % scopes.length : 0
            scope = scopes[next_index]
            matches = spell_ranked_matches_for_scope(word, scope)

            {
              scope: scope,
              suggestions: spell_suggestions_from_matches(matches),
            }
          end

          def best_spell_lookup(word, scopes)
            results = Array(scopes).each_with_index.map do |scope, index|
              matches = spell_ranked_matches_for_scope(word, scope)
              {
                scope: scope,
                scope_index: index,
                matches: matches,
                suggestions: spell_suggestions_from_matches(matches),
              }
            end
            return { scope: scopes.first, suggestions: [] } if results.empty?

            populated = results.reject { |result| result[:suggestions].empty? }
            selected = if populated.empty?
                         results.first
                       else
                         populated.max_by do |result|
                           top_match = result[:matches].first
                           [
                             top_match ? top_match[:similarity].to_f : -Float::INFINITY,
                             result[:suggestions].length,
                             -result[:scope_index]
                           ]
                         end
                       end

            {
              scope: selected[:scope],
              suggestions: selected[:suggestions],
            }
          end

          def same_spell_target?(state, target)
            return false unless state.is_a?(Hash) && target.is_a?(Hash)

            state_word = (state[:word] || state['word']).to_s.strip
            target_word = (target[:word] || target['word']).to_s.strip
            state_start = integer_value(state[:start] || state['start'])
            state_end = integer_value(state[:end] || state['end'])
            target_start = integer_value(target[:start] || target['start'])
            target_end = integer_value(target[:end] || target['end'])

            state_word.casecmp(target_word).zero? &&
              state_start == target_start &&
              state_end == target_end
          end

          def fetch_spell_matches(word, strategy)
            case strategy[:mode]
            when :source
              Array(@dictionary_service.fuzzy_search(
                      word,
                      source_lang: strategy[:source],
                      target_lang: strategy[:target],
                      limit: SPELL_SUGGESTION_FETCH_LIMIT
                    ))
            when :translations
              Array(@dictionary_service.fuzzy_search_translations(
                      word,
                      source_lang: strategy[:source],
                      target_lang: strategy[:target],
                      limit: SPELL_SUGGESTION_FETCH_LIMIT
                    ))
            else
              []
            end
          end

          def spell_lookup_scopes
            pairs = Array(@dictionary_service&.available_language_pairs).filter_map { |pair| normalize_pair(pair) }
            return [] if pairs.empty?

            prioritized_spell_languages(pairs).filter_map do |language|
              strategies = spell_lookup_strategies(language, pairs)
              next if strategies.empty?

              {
                key: "lang:#{language}",
                label: spell_language_label(language),
                strategies: strategies,
              }
            end
          end

          def prioritized_spell_languages(pairs)
            normalize_languages(
              [
                @dictionary_service&.configured_source_lang,
                @dictionary_service&.configured_target_lang,
                'de',
                'en',
              ] +
              pairs.flat_map { |pair| [pair[:source], pair[:target]] }
            )
          end

          def normalize_languages(values)
            Array(values).filter_map { |value| normalize_language(value) }.uniq
          end

          def spell_lookup_strategies(language, pairs)
            target_priority = prioritized_spell_targets(language, pairs)
            source_strategies = pairs
                                .select { |pair| pair[:source] == language }
                                .sort_by { |pair| [target_priority.index(pair[:target]) || target_priority.length, pair[:target]] }
                                .map do |pair|
              { mode: :source, source: pair[:source], target: pair[:target] }
            end
            translation_strategies = pairs
                                     .select { |pair| pair[:target] == language }
                                     .sort_by { |pair| [target_priority.index(pair[:source]) || target_priority.length, pair[:source]] }
                                     .map do |pair|
              { mode: :translations, source: pair[:source], target: pair[:target] }
            end

            source_strategies + translation_strategies
          end

          def prioritized_spell_targets(language, pairs)
            normalize_languages(
              [
                @dictionary_service&.configured_target_lang,
                @dictionary_service&.configured_source_lang,
              ] +
              pairs.flat_map { |pair| [pair[:source], pair[:target]] } -
              [language]
            )
          end

          def spell_language_label(language)
            Dictionary::Constants::LANGUAGE_LABELS[language] || language.to_s.upcase
          end

          def normalize_pair(pair)
            return nil unless pair.is_a?(Hash)

            source = normalize_language(pair[:source] || pair['source'])
            target = normalize_language(pair[:target] || pair['target'])
            return nil if source.nil? || target.nil?

            { source: source, target: target }
          end

          def normalize_language(value)
            normalized = value.to_s.strip.downcase
            normalized.empty? ? nil : normalized
          end

          def integer_value(value)
            Shoko::Shared::TypeCoercion.optional_integer(value)
          end
        end
      end
    end
  end
end
