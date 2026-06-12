# frozen_string_literal: true

require_relative 'support/message_notifier'
require_relative 'support/session_outcome_helpers'
require_relative '../../../shared/text_sanitizer'
require_relative '../../../shared/language_directory'

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
          include Shoko::Adapters::Input::Controllers::Support::MessageNotifier
          include Shoko::Adapters::Input::Controllers::Support::SessionOutcomeHelpers

          LanguageDirectory = Shoko::Shared::LanguageDirectory

          # async_relay is the injected result relay (composition provides an
          # AsyncResultRelay): translations run through it off the UI thread
          # and their results drain back on the reader's event loop.
          def initialize(reader_state:, reader_session_mutator:, translation_service:, translator_ui_session:,
                         async_relay:, input_controller: nil, selection_service: nil, rendered_content_reader: nil,
                         notification_service: nil, logger: nil)
            @reader_state = reader_state
            @reader_session_mutator = reader_session_mutator
            @translation_service = translation_service
            @translator_ui_session = translator_ui_session
            @input_controller = input_controller
            @selection_service = selection_service
            @rendered_content_reader = rendered_content_reader
            @notification_service = notification_service
            @async_relay = async_relay
            @logger = logger
            raise ArgumentError, 'notification_service is required' if @notification_service.nil?
            raise ArgumentError, 'async_relay is required' if @async_relay.nil?
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

            ensure_languages
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

          # ↵ : apply the highlighted language (picker) or translate (editor).
          def translator_confirm(_key = nil)
            picker_open? ? apply_picker_selection : submit_translation
            :handled
          rescue Shoko::Error => e
            @logger&.debug('translator.confirm_failed', error: e.message)
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
            ensure_languages
            next_side = @reader_state.translator_picker_side&.to_sym == :target ? :source : :target
            @translator_ui_session.open_picker(next_side)
            set_message(picker_hint(next_side), 2)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('translator.cycle_picker_failed', error: e.message)
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

          private

          # ----- source editor -----

          def edit_source(edit_op)
            text = @reader_state.translator_query.to_s
            cursor = clamp_cursor(@reader_state.translator_cursor.to_i, text.length)
            new_text, new_cursor = apply_source_edit(text, cursor, edit_op)
            @translator_ui_session.write_source(text: new_text, cursor: new_cursor)
          end

          def apply_source_edit(text, cursor, edit_op)
            case edit_op&.operation
            when :insert    then insert_at(text, cursor, edit_op.text.to_s)
            when :newline   then insert_at(text, cursor, "\n", literal: true)
            when :backspace then backspace_at(text, cursor)
            when :delete    then delete_at(text, cursor)
            else [text, cursor]
            end
          end

          def insert_at(text, cursor, char, literal: false)
            return [text, cursor] unless literal || Shoko::Shared::TextSanitizer.printable_char?(char)

            ["#{text[0...cursor]}#{char}#{text[cursor..]}", cursor + char.length]
          end

          def backspace_at(text, cursor)
            return [text, cursor] if cursor <= 0

            ["#{text[0...(cursor - 1)]}#{text[cursor..]}", cursor - 1]
          end

          def delete_at(text, cursor)
            return [text, cursor] if cursor >= text.length

            ["#{text[0...cursor]}#{text[(cursor + 1)..]}", cursor]
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
            cursor = clamp_cursor(@reader_state.translator_cursor.to_i, text.length)
            target = case direction
                     when :left  then [cursor - 1, 0].max
                     when :right then [cursor + 1, text.length].min
                     when :home  then 0
                     when :end   then text.length
                     else cursor
                     end
            @translator_ui_session.write_cursor(target) if target != cursor
          end

          def clamp_cursor(cursor, length)
            cursor.clamp(0, length)
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
          # LibreTranslate server cannot freeze the reader; the event loop's
          # translator poll drains the result onto this thread.
          def translate_text(text, announce: false)
            text = text.to_s.strip
            return if text.empty?

            source_lang = @reader_state.translator_source_lang.to_s
            target_lang = @reader_state.translator_target_lang.to_s
            set_message('Translating…', 2)
            @async_relay.submit { perform_translation(text, source_lang, target_lang, announce) }
          end

          # Worker-side: compute only; the result applies on the UI thread.
          def perform_translation(text, source_lang, target_lang, announce)
            result = @translation_service.translate(text, source_lang: source_lang, target_lang: target_lang)
            @async_relay.enqueue do
              @translator_ui_session.apply_result(result, query: text)
              announce_translation(result) if announce
            end
          end
          private :perform_translation

          def retranslate_if_present
            translate_text(@reader_state.translator_query.to_s.strip)
          end

          def announce_translation(result)
            if result.respond_to?(:error?) && result.error?
              set_message('Translation failed — is LibreTranslate running?', 3)
            else
              set_message("Translated to #{LanguageDirectory.name_for(@reader_state.translator_target_lang)}", 2)
            end
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
            when :backspace then text[0...-1].to_s
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

          # The picker uses the curated language directory, populated instantly so the
          # list is interactive the moment the picker opens — no network round-trip on
          # the way in. (Translation itself still goes to the live backend on ↵.)
          def ensure_languages
            return unless Array(@reader_state.translator_languages).empty?

            @translator_ui_session.apply_languages(LanguageDirectory.fallback_languages)
          end

          # ----- prefill from a selection payload -----

          def prefill_and_translate(payload)
            text = selection_text(payload)
            if text && !text.empty?
              @translator_ui_session.write_source(text: text, cursor: text.length)
              translate_text(text, announce: true)
            else
              set_message('Translate: type text · ↵ translate · Tab languages', 3)
            end
          end

          def selection_text(payload)
            return nil unless payload.is_a?(Hash)
            return nil unless @selection_service && @rendered_content_reader

            range = payload.dig(:data, :selection_range) || @reader_state.selection
            text = @selection_service.extract_text(range, @rendered_content_reader.rendered_lines)
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
            return '' unless result.respond_to?(:detected_source_lang)

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
