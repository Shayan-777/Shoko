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
      Shoko::Core::Models::Session::MenuSessionSnapshot.build(
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
      Shoko::Core::Models::Session::MenuTransientSnapshot.build(
        translator_languages: [
          { code: 'en', name: 'English' },
          { code: 'de', name: 'German' },
        ]
      )
    )
  end
  let(:menu_mode_control) { instance_double('MenuModeControl', activate_menu_mode: nil) }
  let(:translator_workflow) do
    instance_double('MenuStateController', fetch_translation_languages: [], translate_text: nil)
  end

  subject(:action) do
    described_class.new(
      menu_session_store: menu_session_store,
      menu_mode_control: menu_mode_control,
      translator_workflow: translator_workflow,
      menu_transient_store: menu_transient_store
    )
  end

  it 'inserts typed text into the input buffer' do
    payload = Shoko::Application::UseCases::Requests::TextInput.new(text: 'H')

    action.call(:translator_input_insert_text, payload)
    snapshot = Shoko::Core::Models::Session::MenuSnapshot.build(
      menu_session_store.load.to_h.merge(menu_transient_store.load.to_h)
    )

    expect(snapshot.translator_input_text).to eq('H')
    expect(snapshot.translator_input_cursor).to eq(1)
  end

  it 'opens the source dropdown when source focus is activated' do
    menu_session_store.save(menu_session_store.load.with(translator_focus: :source))

    action.call(:translator_activate_focus)
    snapshot = menu_session_store.load

    expect(snapshot.mode).to eq(:translator_source_dropdown)
    expect(snapshot.translator_dropdown_selected).to eq(0)
    expect(menu_mode_control).to have_received(:activate_menu_mode).with(:translator_source_dropdown)
  end

  it 'submits translations when enter is pressed in the input box' do
    menu_session_store.save(menu_session_store.load.with(translator_input_text: 'Hallo', translator_input_cursor: 5))

    action.call(:translator_activate_focus)

    expect(translator_workflow).to have_received(:translate_text).with(
      text: 'Hallo',
      source_lang: 'auto',
      target_lang: 'en'
    )
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
    expect(menu_mode_control).to have_received(:activate_menu_mode).with(:translator)
    expect(translator_workflow).to have_received(:translate_text).with(
      text: 'Hallo',
      source_lang: 'auto',
      target_lang: 'de'
    )
  end
end
