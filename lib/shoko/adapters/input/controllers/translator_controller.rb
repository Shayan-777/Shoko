# frozen_string_literal: true

require 'shoko/core/services/text_buffer_edit'
require 'shoko/core/services/grapheme_cursor'
require 'shoko/application/use_cases/requests/edit_op'
require_relative 'support/message_notifier'
require_relative 'support/session_outcome_access'
require 'shoko/shared/text_sanitizer'
require 'shoko/core/services/language_directory'
require_relative 'translator_language_session'
require_relative 'translator_request_runner'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Drives the in-book translator as a first-class reader mode. Unlike the
        # in-book search and dictionary bars — whose single-line query lives on the
        # status bar — the translator is a small workspace: the source text is a
        # multi-line editor *inside* the left-docked card (the status bar becomes a
        # toolbar), so you can compose more than a sentence and watch it wrap.
        #
        # The source text and a character cursor live in the reader view-state store
        # and are written through the translator UI session (the card re-renders from
        # them); this controller owns the operations that need adapter coordination:
        # surface lifecycle + modal mode, running the translation service, populating
        # the language list, and the contextual input handling that routes the same
        # keys to either the source editor or the open language picker.
        #
        # Two faces, switched by the picker side in state:
        #   * editor mode — printable keys insert at the cursor; ←/→/Home/End move it,
        #     Backspace/Delete edit, ↑/↓ scroll the translation, ↵ translates, Tab
        #     opens the language picker, ⇧Tab swaps the pair; and
        #   * picker mode — type to filter languages, ↑/↓ move, ←/→ (or Tab) flip
        #     Source⇄Target, ↵ applies the language and re-translates, Esc backs out.
        class TranslatorController
          TextBufferEdit = Shoko::Core::Services::TextBufferEdit
          GraphemeCursor = Shoko::Core::Services::GraphemeCursor

          include Shoko::Adapters::Input::Controllers::Support::MessageNotifier
          include Shoko::Adapters::Input::Controllers::Support::SessionOutcomeAccess

          LanguageDirectory = Shoko::Core::Services::LanguageDirectory

          # The two collaborators used only to pull text out of a live selection
          # (the popup "Translate" prefill), kept as one parameter so the
          # constructor stays within the dependency budget.
          SelectionTextSource = Data.define(:selection_service, :rendered_content_reader)
          BUTTON_FEEDBACK_SECONDS = 1.0 # how long the Pasted!/Copied! flash stays up

          # async_relay is the injected result relay (composition provides an
          # AsyncResultRelay): translations run through it off the UI thread
          # and their results drain back on the reader's event loop.
          def initialize(reader_state:, reader_session_mutator:, translation_service:, translator_ui_session:,
                         async_relay:, input_controller: nil, selection_text_source: nil,
                         clipboard_service: nil, notification_service: nil, logger: nil)
            @reader_state = reader_state
            @reader_session_mutator = reader_session_mutator
            @translation_service = translation_service
            @translator_ui_session = translator_ui_session
            @input_controller = input_controller
            @selection_text_source = selection_text_source
            @clipboard_service = clipboard_service
            @notification_service = notification_service
            @async_relay = async_relay
            @logger = logger
            raise ArgumentError, 'notification_service is required' if @notification_service.nil?
            raise ArgumentError, 'async_relay is required' if @async_relay.nil?

            @language_session = TranslatorLanguageSession.new(
              reader_state: reader_state,
              translator_ui_session: translator_ui_session,
              translation_service: translation_service,
              async_relay: async_relay,
              on_message: method(:set_message),
              on_pending_translation: method(:translate_text)
            )
            @request_runner = TranslatorRequestRunner.new(
              reader_state: reader_state,
              translation_service: translation_service,
              ui_session: translator_ui_session,
              async_relay: async_relay,
              on_message: method(:set_message)
            )
          end

          # Applies pending translation results on the UI thread; called from
          # the reader event loop.
          def drain_async_results
            @async_relay.drain!
          end

          # True while a translation is in flight or awaiting drain — keeps the
          # event loop polling so the result lands without a keypress.
          def async_pending?
            @async_relay.busy?
          end

          # Open the translator. A selection payload (from the popup "Translate"
          # action) pre-fills the source editor and translates it immediately; the
          # ⇧T hotkey (nil payload) opens an empty workspace to type into.
          def open_translator(payload = nil)
            outcome = @translator_ui_session.open
            return :pass unless session_ok?(outcome)

            activate_translator_mode
            prefill_and_translate(payload)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('translator.open_failed', error: e.message)
            :pass
          end

          # Esc is contextual: a tap first backs out of the language picker (to the
          # editor); a second tap closes the translator entirely.
          def close_translator(_key = nil)
            return close_picker if picker_open?
            return :pass unless @translator_ui_session.visible? || @reader_state.mode == :translator

            @request_runner.invalidate
            @language_session.clear_pending
            outcome = @translator_ui_session.close
            return :pass unless session_ok?(outcome)

            deactivate_translator_mode
            :handled
          rescue Shoko::Error => e
            @logger&.debug('translator.close_failed', error: e.message)
            :pass
          end

          # Printable input + backspace/delete, routed to the picker filter when the
          # picker is open, otherwise edited at the cursor in the source editor.
          def edit_translator(edit_op)
            picker_open? ? edit_picker_filter(edit_op) : edit_source(edit_op)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('translator.edit_failed', error: e.message)
            :pass
          end

          # ↵ : apply the highlighted language (picker) or insert a newline
          # (editor), matching the menu translator's multi-line text field.
          def translator_confirm(_key = nil)
            if picker_open?
              apply_picker_selection
            else
              edit_source(
                Shoko::Application::UseCases::Requests::EditOp.new(operation: :newline)
              )
            end
            :handled
          rescue Shoko::Error => e
            @logger&.debug('translator.confirm_failed', error: e.message)
            :pass
          end

          # Alt/Ctrl+Enter submits on both translator surfaces.
          def translator_submit(_key = nil)
            picker_open? ? apply_picker_selection : submit_translation
            :handled
          rescue Shoko::Error => e
            @logger&.debug('translator.submit_failed', error: e.message)
            :pass
          end

          # Arrow / Home / End, routed contextually: editor caret + translation scroll,
          # or picker selection + side flip.
          def translator_cursor_move(direction)
            picker_open? ? picker_navigate(direction) : source_navigate(direction)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('translator.cursor_move_failed', error: e.message)
            :pass
          end

          # Tab : open the picker on the Target side; once open, flip Source⇄Target.
          def translator_cycle_picker(_key = nil)
            next_side = @reader_state.translator_picker_side&.to_sym == :target ? :source : :target
            translator_open_picker(next_side)
          end

          # Open the language picker directly on a chosen side — the mouse path for
          # clicking the source/target label on the rule. Inside the picker this
          # flips to that side; clicking the side that is already active is a no-op
          # (so a typed filter is not discarded).
          def translator_open_picker(side)
            side = side&.to_sym
            return :pass unless %i[source target].include?(side)
            return :handled if @reader_state.translator_picker_side&.to_sym == side

            ensure_languages
            @translator_ui_session.open_picker(side)
            set_message(picker_hint(side), 2)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('translator.open_picker_failed', error: e.message)
            :pass
          end

          # ⇧Tab : swap source and target, then re-translate in place. When the
          # source was auto-detect, the detected language (if known) takes the new
          # target slot so the round-trip is meaningful.
          def translator_swap_languages(_key = nil)
            new_source, new_target = swapped_pair
            @translator_ui_session.apply_pair(source: new_source, target: new_target)
            retranslate_if_present
            set_message("Translate: #{pair_label(new_source, new_target)}", 2)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('translator.swap_failed', error: e.message)
            :pass
          end

          def refresh_theme(theme_context:)
            @translator_ui_session&.refresh_theme(color_mode: theme_context&.color_mode)
          end

          def translator_visible?
            @translator_ui_session.visible? == true
          end

          # Paste button: drop the clipboard's text into the source well at the
          # caret, then translate it (the editor's reason for existing). Success is
          # confirmed on the button itself (a 1s "Pasted!" flash), so only the
          # failure cases — empty/unreadable clipboard — raise a toast.
          def translator_paste_source(_key = nil)
            return :handled unless @clipboard_service

            text = @clipboard_service.read_text
            return paste_unavailable if text.nil?

            text = text.to_s
            return paste_empty if text.strip.empty?

            insert_source_text(text)
            submit_translation
            flash_button_feedback(:pasted)
            :handled
          rescue Shoko::ClipboardError, Shoko::Error => e
            set_message("Paste failed: #{e.message}", 2)
            :handled
          end

          # Copy button: put the current translation on the clipboard. Success
          # flashes "Copied!" on the button; only the failures raise a toast.
          def translator_copy_translation(_key = nil)
            text = current_translation_text
            return copy_nothing if text.empty?
            return :handled unless @clipboard_service

            if @clipboard_service.copy_text?(text)
              flash_button_feedback(:copied)
            else
              set_message('Failed to copy to clipboard', 2)
            end
            :handled
          rescue Shoko::ClipboardError, Shoko::Error => e
            set_message("Copy failed: #{e.message}", 2)
            :handled
          end

          private

          # Light up the button with its confirmation label for ~1s. The translator
          # editor already redraws continuously (the source caret blinks), so the
          # label reverts on its own once this expires — no extra loop keep-alive.
          def flash_button_feedback(kind)
            @reader_session_mutator.update_reader(
              translator_feedback: { kind: kind, until: monotonic_now + BUTTON_FEEDBACK_SECONDS }
            )
          end

          def monotonic_now
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end

          def paste_unavailable
            set_message('Clipboard is unavailable', 2)
            :handled
          end

          def paste_empty
            set_message('Clipboard is empty', 2)
            :handled
          end

          def copy_nothing
            set_message('Nothing to copy yet', 2)
            :handled
          end

          def insert_source_text(text)
            current = @reader_state.translator_query.to_s
            cursor = clamp_cursor(current, @reader_state.translator_cursor)
            sanitized = sanitize_pasted_text(text)
            return if sanitized.empty?

            new_text, new_cursor = TextBufferEdit.insert_at(current, cursor, sanitized, literal: true)
            @translator_ui_session.write_source(text: new_text, cursor: new_cursor)
          end

          def sanitize_pasted_text(text)
            Shoko::Shared::TextSanitizer.sanitize(text.to_s, preserve_newlines: true, preserve_tabs: false)
          end

          def current_translation_text
            result = @reader_state.translator_result
            result ? result.translated_text.to_s.strip : ''
          end

          # ----- source editor -----

          def edit_source(edit_op)
            text = @reader_state.translator_query.to_s
            cursor = clamp_cursor(text, @reader_state.translator_cursor)
            new_text, new_cursor = TextBufferEdit.apply(text, cursor, edit_op)
            @translator_ui_session.write_source(text: new_text, cursor: new_cursor)
          end

          def source_navigate(direction)
            case direction
            when :left, :right, :home, :end then move_source_cursor(direction)
            when :up   then scroll_result(-1)
            when :down then scroll_result(1)
            end
          end

          def move_source_cursor(direction)
            text = @reader_state.translator_query.to_s
            cursor = clamp_cursor(text, @reader_state.translator_cursor)
            target = case direction
                     when :left  then GraphemeCursor.previous(text, cursor)
                     when :right then GraphemeCursor.next(text, cursor)
                     when :home  then 0
                     when :end   then text.length
                     else cursor
                     end
            @translator_ui_session.write_cursor(target) if target != cursor
          end

          def clamp_cursor(text, cursor)
            GraphemeCursor.clamp(text, cursor)
          end

          def scroll_result(delta)
            current = @reader_state.translator_scroll.to_i
            @translator_ui_session.apply_scroll([current + delta.to_i, 0].max)
          end

          # ----- translation -----

          def submit_translation
            translate_text(@reader_state.translator_query.to_s.strip, announce: true)
          end

          # Translate a concrete piece of text against the current pair and publish
          # the result. Used by ↵ (reading the editor) and by the popup-prefill path
          # (translating the text it just extracted, no state round-trip).
          #
          # The HTTP call runs through the async relay so a slow or unreachable
          # translation backend cannot freeze the reader; the event loop's
          # translator poll drains the result onto this thread.
          def translate_text(text, announce: false)
            text = text.to_s.strip
            return if text.empty?

            unless @language_session.available?
              @language_session.defer_translation(text: text, announce: announce)
              ensure_languages
              return
            end

            @request_runner.submit(text, announce: announce)
          end

          def retranslate_if_present
            translate_text(@reader_state.translator_query.to_s.strip)
          end

          # ----- language picker -----

          def edit_picker_filter(edit_op)
            query = apply_filter_edit(@reader_state.translator_picker_query.to_s, edit_op)
            @translator_ui_session.apply_picker(query: query, index: 0)
          end

          def apply_filter_edit(text, edit_op)
            case edit_op&.operation
            when :insert
              char = edit_op.text.to_s
              Shoko::Shared::TextSanitizer.printable_char?(char) ? "#{text}#{char}" : text
            when :backspace then TextBufferEdit.backspace_at(text, text.length).first
            else text
            end
          end

          def picker_navigate(direction)
            case direction
            when :up    then move_picker(-1)
            when :down  then move_picker(1)
            when :home  then select_candidate(0)
            when :end   then select_candidate(picker_candidates.length - 1)
            when :left  then flip_picker_side(:source)
            when :right then flip_picker_side(:target)
            end
          end

          def move_picker(delta)
            candidates = picker_candidates
            return if candidates.empty?

            select_candidate((@reader_state.translator_picker_index.to_i + delta.to_i).clamp(0, candidates.length - 1))
          end

          def select_candidate(index)
            @translator_ui_session.apply_picker(
              query: @reader_state.translator_picker_query.to_s, index: [index, 0].max
            )
          end

          def flip_picker_side(side)
            return if @reader_state.translator_picker_side&.to_sym == side

            @translator_ui_session.open_picker(side)
          end

          def apply_picker_selection
            candidates = picker_candidates
            return close_picker if candidates.empty?

            index = @reader_state.translator_picker_index.to_i.clamp(0, candidates.length - 1)
            code = candidates[index][:code].to_s
            apply_language(@reader_state.translator_picker_side&.to_sym, code)
            close_picker_silently
            retranslate_if_present
            set_message("Translate: #{current_pair_label}", 2)
          end

          def apply_language(side, code)
            if side == :source
              @translator_ui_session.apply_pair(source: code, target: @reader_state.translator_target_lang.to_s)
            else
              @translator_ui_session.apply_pair(source: @reader_state.translator_source_lang.to_s, target: code)
            end
          end

          def picker_candidates
            LanguageDirectory.candidates_for(
              @reader_state.translator_languages,
              side: @reader_state.translator_picker_side,
              source_code: @reader_state.translator_source_lang,
              query: @reader_state.translator_picker_query.to_s
            )
          end

          def close_picker
            close_picker_silently
            :handled
          end

          def close_picker_silently
            @translator_ui_session.close_picker
          end

          def picker_open?
            !@reader_state.translator_picker_side.nil?
          end

          # ----- languages -----

          def ensure_languages
            @language_session.ensure_loaded
          end

          # ----- prefill from a selection payload -----

          def prefill_and_translate(payload)
            text = selection_text(payload)
            if text && !text.empty?
              @translator_ui_session.write_source(text: text, cursor: text.length)
              if Array(@reader_state.translator_languages).empty?
                @language_session.defer_translation(text: text, announce: true)
                ensure_languages
              else
                translate_text(text, announce: true)
              end
            else
              ensure_languages
              set_message('Translate: type text · ↵ translate · Tab languages', 3)
            end
          end

          def selection_text(payload)
            return nil unless payload.is_a?(Hash)

            source = @selection_text_source
            return nil unless source&.selection_service && source.rendered_content_reader

            range = payload.dig(:data, :selection_range) || @reader_state.selection
            text = source.selection_service.extract_text(range, source.rendered_content_reader.rendered_lines)
            cleaned = text.to_s.strip.gsub(/\s+/, ' ')
            cleaned.empty? ? nil : cleaned
          end

          # ----- language helpers -----

          # The flipped pair. The old target becomes the new source; the old source
          # becomes the new target — resolving auto-detect to the detected language
          # when one is known, and defaulting away from a degenerate same-language
          # pair otherwise.
          def swapped_pair
            source = @reader_state.translator_source_lang.to_s
            target = @reader_state.translator_target_lang.to_s
            resolved_source = source.strip.casecmp?(LanguageDirectory::AUTO) ? detected_source : source
            new_source = target.strip.empty? ? 'en' : target
            new_target = resolved_source.to_s.strip.empty? ? 'en' : resolved_source
            new_target = new_source.casecmp?('en') ? 'de' : 'en' if new_source.casecmp?(new_target)
            [new_source, new_target]
          end

          def detected_source
            result = @reader_state.translator_result
            return '' unless result

            result.detected_source_lang.to_s
          end

          def picker_hint(side)
            "Languages: #{side == :source ? 'Source' : 'Target'} · type filter · ←/→ switch · ↵ pick"
          end

          def current_pair_label
            pair_label(@reader_state.translator_source_lang, @reader_state.translator_target_lang)
          end

          def pair_label(source, target)
            "#{code_label(source)} → #{code_label(target)}"
          end

          def code_label(code)
            code.to_s.strip.casecmp?(LanguageDirectory::AUTO) ? 'auto' : code.to_s.strip.downcase
          end

          def activate_translator_mode
            @input_controller&.enter_modal_mode(:translator)
          end

          def deactivate_translator_mode
            @input_controller&.exit_modal_mode(:translator)
          end
        end
      end
    end
  end
end
