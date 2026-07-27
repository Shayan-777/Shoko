# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::Menu::Actions::Translator do
  let(:menu_session_store_class) do
    Class.new do
      include Shoko::Application::Ports::Outbound::MenuSessionStore

      def initialize(snapshot)
        @snapshot = snapshot
      end

      def load
        @snapshot
      end

      def save(snapshot)
        @snapshot = snapshot
      end
    end
  end

  let(:menu_transient_store_class) do
    Class.new do
      include Shoko::Application::Ports::Outbound::MenuTransientStore

      def initialize(snapshot)
        @snapshot = snapshot
      end

      def load
        @snapshot
      end

      def save(snapshot)
        @snapshot = snapshot
      end
    end
  end

  let(:menu_session_store) do
    menu_session_store_class.new(
      Shoko::Application::Ports::Outbound::State::MenuSessionSnapshot.build(
        mode: :translator,
        translator_input_text: '',
        translator_input_cursor: 0,
        translator_source_lang: 'auto',
        translator_target_lang: 'en',
        translator_focus: :input,
        translator_dropdown_selected: 0
      )
    )
  end
  let(:menu_transient_store) do
    menu_transient_store_class.new(
      Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot.build(
        translator_languages: [
          { code: 'en', name: 'English' },
          { code: 'de', name: 'German' },
        ]
      )
    )
  end
  let(:translator_workflow) do
    instance_double(Shoko::Adapters::Input::Controllers::Menu::StateController, fetch_translation_languages: [], translate_text: nil)
  end
  let(:menu_translator_control) { double('MenuTranslatorControl', move_translator_cursor: nil) }

  subject(:action) do
    described_class.new(
      menu_session_store: menu_session_store,
      translator_workflow: translator_workflow,
      menu_translator_control: menu_translator_control,
      menu_transient_store: menu_transient_store
    )
  end

  def reload
    Shoko::Application::Ports::Outbound::State::MenuSnapshot.build(
      menu_session_store.load.to_h.merge(menu_transient_store.load.to_h)
    )
  end

  it 'returns to the RSS article when translation was opened from an RSS selection' do
    menu_session_store.save(menu_session_store.load.with(translator_return_mode: :rss_reader))

    action.call(:close_translator_mode)

    expect(reload.mode).to eq(:rss_reader)
    expect(reload.translator_return_mode).to be_nil
  end

  it 'inserts typed text into the input buffer' do
    payload = Shoko::Application::UseCases::Requests::EditOp.new(operation: :insert, text: 'H')

    action.call(:edit_translator_input, payload)
    snapshot = Shoko::Application::Ports::Outbound::State::MenuSnapshot.build(
      menu_session_store.load.to_h.merge(menu_transient_store.load.to_h)
    )

    expect(snapshot.translator_input_text).to eq('H')
    expect(snapshot.translator_input_cursor).to eq(1)
  end

  it 'types a capital S while editing instead of swapping languages' do
    action.call(:translator_swap_languages)

    expect(reload.translator_input_text).to eq('S')
    expect(reload.translator_source_lang).to eq('auto')
  end

  it 'swaps languages when S is pressed from a language panel' do
    menu_session_store.save(
      menu_session_store.load.with(translator_focus: :source, translator_source_lang: 'de', translator_target_lang: 'en')
    )

    action.call(:translator_swap_languages)
    snapshot = menu_session_store.load

    expect(snapshot.translator_source_lang).to eq('en')
    expect(snapshot.translator_target_lang).to eq('de')
  end

  it 'opens the source dropdown when source focus is activated' do
    menu_session_store.save(menu_session_store.load.with(translator_focus: :source))

    action.call(:translator_activate_focus)
    snapshot = menu_session_store.load

    expect(snapshot.mode).to eq(:translator_source_dropdown)
    expect(snapshot.translator_dropdown_selected).to eq(0)
  end

  it 'inserts a newline (note-editor parity) when enter is pressed while editing' do
    menu_session_store.save(menu_session_store.load.with(translator_input_text: 'Hallo', translator_input_cursor: 5))

    action.call(:translator_activate_focus)

    expect(reload.translator_input_text).to eq("Hallo\n")
    expect(reload.translator_input_cursor).to eq(6)
    expect(translator_workflow).not_to have_received(:translate_text)
  end

  it 'deletes the character at the cursor on forward-delete' do
    menu_session_store.save(menu_session_store.load.with(translator_input_text: 'abc', translator_input_cursor: 1))

    action.call(:edit_translator_input, Shoko::Application::UseCases::Requests::EditOp.new(operation: :delete))

    expect(reload.translator_input_text).to eq('ac')
    expect(reload.translator_input_cursor).to eq(1)
  end

  it 'translates when translator_submit (Alt+Enter) is invoked' do
    menu_session_store.save(menu_session_store.load.with(translator_input_text: 'Hallo', translator_input_cursor: 5))

    action.call(:translator_submit)

    expect(translator_workflow).to have_received(:translate_text).with(
      text: 'Hallo',
      source_lang: 'auto',
      target_lang: 'en'
    )
  end

  it 'converts "- " into a bullet via the shared editor operator' do
    insert = ->(text) { action.call(:edit_translator_input, Shoko::Application::UseCases::Requests::EditOp.new(operation: :insert, text: text)) }
    insert.call('-')
    insert.call(' ')

    expect(reload.translator_input_text).to eq('● ')
  end

  it 'continues a bulleted list when enter is pressed on a bullet line' do
    menu_session_store.save(menu_session_store.load.with(translator_input_text: '● a', translator_input_cursor: 3))

    action.call(:translator_activate_focus)

    expect(reload.translator_input_text).to eq("● a\n● ")
  end

  it 'forwards arrow-key cursor movement to the translator control' do
    action.call(:move_translator_cursor, Shoko::Application::UseCases::Requests::CursorMove.new(direction: :left))

    expect(menu_translator_control).to have_received(:move_translator_cursor).with(direction: :left)
  end

  it 'applies dropdown selection and retranslates when text is present' do
    menu_session_store.save(
      menu_session_store.load.with(
        mode: :translator_target_dropdown,
        translator_focus: :target,
        translator_input_text: 'Hallo',
        translator_input_cursor: 5,
        translator_dropdown_selected: 1
      )
    )

    action.call(:activate_translator_language_selection)
    snapshot = menu_session_store.load

    expect(snapshot.mode).to eq(:translator)
    expect(snapshot.translator_target_lang).to eq('de')
    expect(translator_workflow).to have_received(:translate_text).with(
      text: 'Hallo',
      source_lang: 'auto',
      target_lang: 'de'
    )
  end
end
