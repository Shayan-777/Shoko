# frozen_string_literal: true

require_relative 'support/session_outcome_construction'
require 'shoko/shared/contracts/session_outcome'

module Shoko
  module Adapters
    module Ui
      module Sessions
        # Adapter-owned lifecycle for the reader translator card. The card renders
        # from the reader view-state store; this session owns the component instance
        # (create/teardown via the factory), the translator-mode flag, and the writes
        # that publish the source text, the translation result, the language pair,
        # the available-language list, and the language-picker selection to state.
        #
        # Mirrors TocUiSessionAdapter / DictionaryUiSessionAdapter: a pure renderer
        # fed from state, with the orchestration (running the translation service,
        # fetching languages, deciding what to write) living in the controller that
        # drives this session.
        class TranslatorUiSessionAdapter
          include Support::SessionOutcomeConstruction

          RESCUABLE_ERRORS = Support::SessionOutcomeConstruction::RESCUABLE_ERRORS

          # Reset on open/close. The chosen language pair and the fetched language
          # list deliberately survive (kept out of this set) so reopening the
          # translator keeps the languages you last picked.
          BLANK_TRANSLATOR_STATE = {
            translator_query: '',
            translator_results_query: '',
            translator_result: nil,
            translator_picker_side: nil,
            translator_picker_query: '',
            translator_picker_index: 0,
            translator_scroll: 0,
            translator_cursor: 0,
          }.freeze

          def initialize(reader_state_reader:, reader_session_mutator:, ui_component_factory:, logger: nil)
            @reader_state_reader = reader_state_reader
            @reader_session_mutator = reader_session_mutator
            @ui_component_factory = ui_component_factory
            @logger = logger
          end

          def open
            popup = ensure_popup
            return failure_outcome(:error, :translator_popup_unavailable, 'Translator popup unavailable') unless popup

            @reader_session_mutator.update_reader(
              translator_lookup_popup: popup, mode: :translator, popup_menu: nil, **BLANK_TRANSLATOR_STATE
            )
            success_outcome(:opened, :translator_opened)
          rescue *RESCUABLE_ERRORS => e
            log_error('translator.session.open', e)
            failure_outcome(:error, :translator_open_failed, e.message)
          end

          def close
            @reader_session_mutator.update_reader(
              translator_lookup_popup: nil, mode: :read, **BLANK_TRANSLATOR_STATE
            )
            success_outcome(:closed, :translator_closed)
          rescue *RESCUABLE_ERRORS => e
            log_error('translator.session.close', e)
            failure_outcome(:error, :translator_close_failed, e.message)
          end

          # Source-editor write: the text plus the caret position (a character index
          # into the text), kept together so the card always renders a caret that
          # matches the buffer.
          def write_source(text:, cursor:)
            @reader_session_mutator.update_reader(
              translator_query: text.to_s, translator_cursor: cursor.to_i
            )
            success_outcome(:handled, :translator_source_written)
          rescue *RESCUABLE_ERRORS => e
            log_error('translator.session.write_source', e)
            failure_outcome(:error, :translator_source_failed, e.message)
          end

          def write_cursor(cursor)
            @reader_session_mutator.update_reader(translator_cursor: cursor.to_i)
            success_outcome(:handled, :translator_cursor_written)
          rescue *RESCUABLE_ERRORS => e
            log_error('translator.session.write_cursor', e)
            failure_outcome(:error, :translator_cursor_failed, e.message)
          end

          # Publish a translation result; the source text that produced it becomes
          # the staleness reference and the result card scroll resets to the top.
          def apply_result(result, query:)
            @reader_session_mutator.update_reader(
              translator_result: result,
              translator_results_query: query.to_s,
              translator_scroll: 0
            )
            success_outcome(:handled, :translator_result_applied)
          rescue *RESCUABLE_ERRORS => e
            log_error('translator.session.apply_result', e)
            failure_outcome(:error, :translator_result_failed, e.message)
          end

          def apply_languages(languages)
            @reader_session_mutator.update_reader(translator_languages: Array(languages))
            success_outcome(:handled, :translator_languages_applied)
          rescue *RESCUABLE_ERRORS => e
            log_error('translator.session.apply_languages', e)
            failure_outcome(:error, :translator_languages_failed, e.message)
          end

          def apply_pair(source:, target:)
            @reader_session_mutator.update_reader(
              translator_source_lang: source.to_s, translator_target_lang: target.to_s
            )
            success_outcome(:handled, :translator_pair_applied)
          rescue *RESCUABLE_ERRORS => e
            log_error('translator.session.apply_pair', e)
            failure_outcome(:error, :translator_pair_failed, e.message)
          end

          def apply_scroll(value)
            @reader_session_mutator.update_reader(translator_scroll: value.to_i)
            success_outcome(:handled, :translator_scroll_applied)
          rescue *RESCUABLE_ERRORS => e
            log_error('translator.session.apply_scroll', e)
            failure_outcome(:error, :translator_scroll_failed, e.message)
          end

          # ----- language picker -----

          def open_picker(side)
            @reader_session_mutator.update_reader(
              translator_picker_side: side, translator_picker_query: '', translator_picker_index: 0
            )
            success_outcome(:handled, :translator_picker_opened)
          rescue *RESCUABLE_ERRORS => e
            log_error('translator.session.open_picker', e)
            failure_outcome(:error, :translator_picker_open_failed, e.message)
          end

          def close_picker
            @reader_session_mutator.update_reader(
              translator_picker_side: nil, translator_picker_query: '', translator_picker_index: 0
            )
            success_outcome(:handled, :translator_picker_closed)
          rescue *RESCUABLE_ERRORS => e
            log_error('translator.session.close_picker', e)
            failure_outcome(:error, :translator_picker_close_failed, e.message)
          end

          def apply_picker(query:, index:)
            @reader_session_mutator.update_reader(
              translator_picker_query: query.to_s, translator_picker_index: index.to_i
            )
            success_outcome(:handled, :translator_picker_applied)
          rescue *RESCUABLE_ERRORS => e
            log_error('translator.session.apply_picker', e)
            failure_outcome(:error, :translator_picker_failed, e.message)
          end

          def visible?
            @reader_state_reader.mode == :translator
          rescue *RESCUABLE_ERRORS => e
            log_error('translator.session.visible?', e)
            false
          end

          def refresh_theme(color_mode:)
            popup = current_popup
            popup&.update_color_mode(color_mode)
            success_outcome(:handled, :translator_theme_refreshed)
          rescue *RESCUABLE_ERRORS => e
            log_error('translator.session.refresh_theme', e)
            failure_outcome(:error, :translator_theme_refresh_failed, e.message)
          end

          private

          def ensure_popup
            current_popup || @ui_component_factory.translator_lookup_popup(reader_state_reader: @reader_state_reader)
          rescue *RESCUABLE_ERRORS => e
            log_error('translator.session.ensure_popup', e)
            nil
          end

          def current_popup
            @reader_state_reader.translator_lookup_popup
          rescue *RESCUABLE_ERRORS => e
            log_error('translator.session.current_popup', e)
            nil
          end
        end
      end
    end
  end
end
