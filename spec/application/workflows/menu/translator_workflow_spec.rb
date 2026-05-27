# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::TranslatorWorkflow do
  class TranslatorWorkflowSpecMenuSessionStore
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

  class TranslatorWorkflowSpecMenuTransientStore
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

  let(:translation_service) { instance_double('TranslationService') }
  let(:menu_session_store) { TranslatorWorkflowSpecMenuSessionStore.new(Shoko::Application::Ports::Outbound::State::MenuSessionSnapshot.build) }
  let(:menu_transient_store) do
    TranslatorWorkflowSpecMenuTransientStore.new(Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot.build)
  end

  subject(:workflow) do
    described_class.new(
      translation_service: translation_service,
      menu_session_store: menu_session_store,
      menu_transient_store: menu_transient_store
    )
  end

  it 'loads languages into transient translator state' do
    allow(translation_service).to receive(:available_languages).and_return(
      [
        Shoko::Core::Models::TranslationLanguage.new(code: 'en', name: 'English'),
        Shoko::Core::Models::TranslationLanguage.new(code: 'de', name: 'German')
      ]
    )

    workflow.fetch_languages
    snapshot = menu_transient_store.load

    expect(snapshot.translator_languages).to eq(
      [
        { code: 'en', name: 'English', targets: [] },
        { code: 'de', name: 'German', targets: [] }
      ]
    )
    expect(snapshot.translator_status).to eq(:ready)
    expect(snapshot.translator_message).to eq('2 languages available.')
  end

  it 'clears translation output for blank input' do
    workflow.translate_text(text: ' ', source_lang: 'auto', target_lang: 'en')

    snapshot = menu_transient_store.load
    expect(snapshot.translator_output_text).to eq('')
    expect(snapshot.translator_status).to eq(:idle)
    expect(snapshot.translator_message).to eq('Type text to translate.')
  end

  it 'stores translated text and detection metadata' do
    allow(translation_service).to receive(:translate).and_return(
      Shoko::Core::Models::TranslationResult.new(
        query: 'Hallo Welt',
        translated_text: 'Hello world',
        source_lang: 'auto',
        target_lang: 'en',
        detected_source_lang: 'de'
      )
    )

    workflow.translate_text(text: 'Hallo Welt', source_lang: 'auto', target_lang: 'en')
    snapshot = menu_transient_store.load

    expect(snapshot.translator_output_text).to eq('Hello world')
    expect(snapshot.translator_detected_source_lang).to eq('de')
    expect(snapshot.translator_status).to eq(:done)
    expect(snapshot.translator_message).to eq('Translated de -> en')
  end
end
