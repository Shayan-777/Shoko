# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::TranslatorController do
  def success_outcome(code: :ok, status: :handled)
    Shoko::Shared::Contracts::SessionOutcome.success(status: status, code: code, payload: nil)
  end

  let(:translator_ui_session) do
    instance_double(
      'TranslatorUiSession',
      open: success_outcome(code: :translator_opened, status: :opened),
      close: success_outcome(code: :translator_closed, status: :closed),
      write_source: success_outcome,
      write_cursor: success_outcome,
      apply_result: success_outcome,
      apply_languages: success_outcome,
      apply_pair: success_outcome,
      apply_scroll: success_outcome,
      open_picker: success_outcome,
      close_picker: success_outcome,
      apply_picker: success_outcome,
      visible?: true
    )
  end
  let(:translation_result) do
    Shoko::Core::Models::TranslationResult.new(
      query: 'hello', translated_text: 'Hallo', source_lang: 'auto', target_lang: 'de'
    )
  end
  let(:translation_service) { instance_double('TranslationService', translate: translation_result) }
  let(:input_controller) { instance_double('InputController', enter_modal_mode: nil, exit_modal_mode: nil) }
  let(:notification_service) { instance_double('NotificationService', set_message: nil) }
  let(:clipboard_service) { instance_double('ClipboardService', read_text: 'world', copy_text?: true) }
  let(:reader_session_mutator) { instance_double('ReaderSessionMutator', update_reader: nil) }

  let(:state) do
    {
      translator_query: 'hello',
      translator_results_query: '',
      translator_result: nil,
      translator_source_lang: 'auto',
      translator_target_lang: 'de',
      translator_languages: [{ code: 'en', name: 'English' }, { code: 'de', name: 'German' }],
      translator_picker_side: nil,
      translator_picker_query: '',
      translator_picker_index: 0,
      translator_scroll: 0,
      translator_cursor: 5, # caret at the end of 'hello'
      mode: :translator,
      selection: nil,
    }
  end

  let(:reader_state) do
    rs = instance_double('ReaderState')
    state.each_key { |field| allow(rs).to receive(field) { state[field] } }
    rs
  end

  subject(:controller) do
    described_class.new(
      reader_state: reader_state,
      reader_session_mutator: reader_session_mutator,
      translation_service: translation_service,
      translator_ui_session: translator_ui_session,
      input_controller: input_controller,
      selection_text_source: nil,
      clipboard_service: clipboard_service,
      notification_service: notification_service,
      async_relay: Shoko::Application::Services::AsyncResultRelay.new,
      logger: nil
    )
  end

  def edit_op(operation, text = nil)
    Shoko::Application::UseCases::Requests::EditOp.new(operation: operation, text: text)
  end

  # The action group unwraps CursorMove to a raw direction symbol before reaching
  # the control port, so the controller's navigation method receives a plain symbol.

  describe '#open_translator' do
    it 'opens the session, seeds the language list, and activates modal mode' do
      state[:translator_languages] = []

      expect(controller.open_translator).to eq(:handled)

      expect(translator_ui_session).to have_received(:open)
      expect(translator_ui_session).to have_received(:apply_languages).with(satisfy { |l| l.any? })
      expect(input_controller).to have_received(:enter_modal_mode).with(:translator)
    end

    it 'pre-fills and translates the selected text when opened from the popup Translate action' do
      state[:translator_query] = ''
      selection_service = instance_double('SelectionService', extract_text: '  Bonjour le  monde ')
      rendered = instance_double('RenderedContentReader', rendered_lines: {})
      selection_text_source = described_class::SelectionTextSource.new(
        selection_service: selection_service, rendered_content_reader: rendered
      )
      controller = described_class.new(
        reader_state: reader_state, reader_session_mutator: instance_double('ReaderSessionMutator', update_reader: nil),
        translation_service: translation_service, translator_ui_session: translator_ui_session,
        input_controller: input_controller, selection_text_source: selection_text_source,
        notification_service: notification_service,
        async_relay: Shoko::Application::Services::AsyncResultRelay.new, logger: nil
      )
      payload = { action: :translate, data: { selection_range: { start: 0, end: 8 } } }

      expect(controller.open_translator(payload)).to eq(:handled)

      expect(translator_ui_session).to have_received(:write_source).with(text: 'Bonjour le monde', cursor: 16)
      expect(translation_service).to have_received(:translate).with('Bonjour le monde', source_lang: 'auto',
                                                                                         target_lang: 'de')
      expect(translator_ui_session).to have_received(:apply_result).with(translation_result,
                                                                         query: 'Bonjour le monde')
    end
  end

  describe '#translator_confirm in text mode' do
    it 'translates the source text with the current pair and publishes the result' do
      expect(controller.translator_confirm).to eq(:handled)

      expect(translation_service).to have_received(:translate).with('hello', source_lang: 'auto', target_lang: 'de')
      expect(translator_ui_session).to have_received(:apply_result).with(translation_result, query: 'hello')
    end
  end

  describe '#edit_translator' do
    it 'inserts a typed character at the caret and advances it' do
      controller.edit_translator(edit_op(:insert, '!')) # caret at 5 (end of 'hello')
      expect(translator_ui_session).to have_received(:write_source).with(text: 'hello!', cursor: 6)
    end

    it 'inserts in the middle of the text at the caret' do
      state[:translator_cursor] = 2 # between 'he' and 'llo'
      controller.edit_translator(edit_op(:insert, 'X'))
      expect(translator_ui_session).to have_received(:write_source).with(text: 'heXllo', cursor: 3)
    end

    it 'backspaces the character before the caret' do
      state[:translator_cursor] = 3 # after 'hel'
      controller.edit_translator(edit_op(:backspace))
      expect(translator_ui_session).to have_received(:write_source).with(text: 'helo', cursor: 2)
    end

    it 'forward-deletes the character at the caret' do
      state[:translator_cursor] = 1 # before 'ello'
      controller.edit_translator(edit_op(:delete))
      expect(translator_ui_session).to have_received(:write_source).with(text: 'hllo', cursor: 1)
    end

    it 'inserts a hard newline at the caret (Shift/Alt+Enter)' do
      state[:translator_cursor] = 5 # end of 'hello'
      controller.edit_translator(edit_op(:newline))
      expect(translator_ui_session).to have_received(:write_source).with(text: "hello\n", cursor: 6)
    end

    it 'routes typing to the language filter while the picker is open' do
      state[:translator_picker_side] = :target
      state[:translator_picker_query] = 'ge'

      controller.edit_translator(edit_op(:insert, 'r'))
      expect(translator_ui_session).to have_received(:apply_picker).with(query: 'ger', index: 0)
    end
  end

  describe '#translator_cursor_move in the source editor' do
    it 'moves the caret left and right' do
      state[:translator_cursor] = 3
      controller.translator_cursor_move(:left)
      expect(translator_ui_session).to have_received(:write_cursor).with(2)

      controller.translator_cursor_move(:right)
      expect(translator_ui_session).to have_received(:write_cursor).with(4)
    end

    it 'jumps the caret home and end' do
      state[:translator_cursor] = 3
      controller.translator_cursor_move(:home)
      expect(translator_ui_session).to have_received(:write_cursor).with(0)

      controller.translator_cursor_move(:end)
      expect(translator_ui_session).to have_received(:write_cursor).with(5)
    end

    it 'scrolls the translation with up/down' do
      state[:translator_scroll] = 2
      controller.translator_cursor_move(:down)
      expect(translator_ui_session).to have_received(:apply_scroll).with(3)
    end
  end

  describe '#translator_cycle_picker' do
    it 'opens the picker on the target side, then flips to source' do
      controller.translator_cycle_picker
      expect(translator_ui_session).to have_received(:open_picker).with(:target)

      state[:translator_picker_side] = :target
      controller.translator_cycle_picker
      expect(translator_ui_session).to have_received(:open_picker).with(:source)
    end
  end

  describe '#translator_paste_source' do
    it 'inserts the clipboard text at the caret, translates it, and flashes Pasted! on the button' do
      allow(translator_ui_session).to receive(:write_source) do |text:, cursor:|
        state[:translator_query] = text
        state[:translator_cursor] = cursor
        success_outcome
      end

      expect(controller.translator_paste_source).to eq(:handled)

      expect(clipboard_service).to have_received(:read_text)
      expect(translator_ui_session).to have_received(:write_source).with(text: 'helloworld', cursor: 10)
      expect(translation_service).to have_received(:translate).with('helloworld', source_lang: 'auto',
                                                                                  target_lang: 'de')
      expect(reader_session_mutator).to have_received(:update_reader)
        .with(hash_including(translator_feedback: hash_including(kind: :pasted)))
    end

    it 'shows a toast and changes nothing when the clipboard is empty' do
      allow(clipboard_service).to receive(:read_text).and_return('')

      expect(controller.translator_paste_source).to eq(:handled)
      expect(translator_ui_session).not_to have_received(:write_source)
      expect(notification_service).to have_received(:set_message).with('Clipboard is empty', 2)
    end
  end

  describe '#translator_copy_translation' do
    it 'copies the current translation and flashes Copied! on the button' do
      state[:translator_result] = translation_result

      expect(controller.translator_copy_translation).to eq(:handled)
      expect(clipboard_service).to have_received(:copy_text?).with('Hallo')
      expect(reader_session_mutator).to have_received(:update_reader)
        .with(hash_including(translator_feedback: hash_including(kind: :copied)))
    end

    it 'reports there is nothing to copy when no translation is on screen' do
      state[:translator_result] = nil

      expect(controller.translator_copy_translation).to eq(:handled)
      expect(clipboard_service).not_to have_received(:copy_text?)
      expect(notification_service).to have_received(:set_message).with('Nothing to copy yet', 2)
    end
  end

  describe '#translator_open_picker' do
    it 'opens the picker directly on the requested side (the mouse path)' do
      expect(controller.translator_open_picker(:source)).to eq(:handled)
      expect(translator_ui_session).to have_received(:open_picker).with(:source)

      controller.translator_open_picker(:target)
      expect(translator_ui_session).to have_received(:open_picker).with(:target)
    end

    it 'ignores an unknown side' do
      expect(controller.translator_open_picker(:sideways)).to eq(:pass)
      expect(translator_ui_session).not_to have_received(:open_picker)
    end
  end

  describe '#translator_confirm in picker mode' do
    it 'applies the highlighted language to the active side and re-translates' do
      state[:translator_picker_side] = :target
      state[:translator_picker_index] = 0 # 'en' (filtered list keeps backend order)

      expect(controller.translator_confirm).to eq(:handled)

      expect(translator_ui_session).to have_received(:apply_pair).with(source: 'auto', target: 'en')
      expect(translator_ui_session).to have_received(:close_picker)
      expect(translation_service).to have_received(:translate)
    end
  end

  describe '#translator_cursor_move in the picker' do
    it 'moves the selection with up/down' do
      state[:translator_picker_side] = :source
      state[:translator_picker_index] = 0

      controller.translator_cursor_move(:down)
      # source side prepends the auto entry, so index 1 is reachable
      expect(translator_ui_session).to have_received(:apply_picker).with(query: '', index: 1)
    end

    it 'flips the active side with left/right' do
      state[:translator_picker_side] = :target

      controller.translator_cursor_move(:left)
      expect(translator_ui_session).to have_received(:open_picker).with(:source)
    end
  end

  describe '#translator_swap_languages' do
    it 'flips the pair and re-translates in place' do
      state[:translator_source_lang] = 'en'
      state[:translator_target_lang] = 'de'

      expect(controller.translator_swap_languages).to eq(:handled)
      expect(translator_ui_session).to have_received(:apply_pair).with(source: 'de', target: 'en')
    end
  end

  describe '#close_translator' do
    it 'backs out of the picker first, leaving the translator open' do
      state[:translator_picker_side] = :target

      expect(controller.close_translator).to eq(:handled)
      expect(translator_ui_session).to have_received(:close_picker)
      expect(translator_ui_session).not_to have_received(:close)
    end

    it 'closes the session and exits modal mode when no picker is open' do
      expect(controller.close_translator).to eq(:handled)
      expect(translator_ui_session).to have_received(:close)
      expect(input_controller).to have_received(:exit_modal_mode).with(:translator)
    end
  end
end
