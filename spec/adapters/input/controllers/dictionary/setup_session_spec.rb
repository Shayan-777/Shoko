# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Dictionary::SetupSession do
  class FakeSetupUiFactory
    def initialize(popup)
      @popup = popup
    end

    def dictionary_popup(_reader_state_reader = nil)
      @popup
    end

    def dictionary_lookup_popup(reader_state_reader:)
      Object.new
    end
  end

  let(:popup) { Shoko::Adapters::Ui::Components::DictionaryPopupComponent.new }
  let(:ui_factory) { FakeSetupUiFactory.new(popup) }
  let(:book_path) { '/books/book-a.epub' }
  let(:reader_state) do
    instance_double(Shoko::Adapters::Runtime::SessionState::ReaderSnapshotProjectionAdapter, selection: nil, dictionary_popup: popup, book_path: book_path)
  end
  let(:config_reader) do
    instance_double(Shoko::Application::Ports::Outbound::State::ConfigSnapshot, dictionary_source_lang: 'auto', dictionary_target_lang: 'en', dictionary_path: nil)
  end
  let(:reader_session_mutator) { instance_double(Shoko::Adapters::Runtime::SessionState::ReaderSessionMutator, update_reader: nil, update_config: nil) }
  let(:dictionary_service) do
    instance_double(Shoko::Core::Services::DictionaryService,
                    configured_source_lang: 'de', configured_target_lang: 'en',
                    available_language_pairs: available_pairs, language_pair_available?: false)
  end
  let(:available_pairs) { [] }
  let(:dictionary_catalog_service) { instance_double(Shoko::Adapters::Storage::DictionaryCatalogService) }
  let(:dictionary_storage) { instance_double(Shoko::Application::Ports::Outbound::DictionaryStorage, ensure_databases_path: '/tmp/shoko-dict') }
  let(:notification_service) { instance_double(Shoko::Adapters::Output::NotificationService, set_message: nil) }
  let(:reader_controller) { instance_double(Shoko::Adapters::Input::Controllers::ReaderController, draw_screen: nil) }
  let(:input_controller) { instance_double(Shoko::Adapters::Input::ReaderInputController, enter_modal_mode: nil, exit_modal_mode: nil) }
  let(:document) { instance_double(Shoko::Application::Models::ReaderDocument, metadata: { language: 'en_US' }, source_path: book_path, language: 'en_US') }
  let(:clock) { instance_double(Shoko::Application::Ports::Outbound::Clock, monotonic_now: 1.0) }
  let(:dictionary_ui_session) do
    Shoko::Adapters::Ui::Sessions::DictionaryUiSessionAdapter.new(
      reader_state_reader: reader_state,
      reader_session_mutator: reader_session_mutator,
      ui_component_factory: ui_factory
    )
  end

  let(:deps_bundle) do
    Shoko::Adapters::Input::Controllers::Dependencies::DictionaryControllerDependencies::Bundle.build(
      reader_state: reader_state,
      config_reader: config_reader,
      reader_session_mutator: reader_session_mutator,
      document: document,
      rendered_content_reader: nil,
      dictionary_service: dictionary_service,
      dictionary_catalog_service: dictionary_catalog_service,
      dictionary_availability: nil,
      dictionary_storage: dictionary_storage,
      selection_service: nil,
      notification_service: notification_service,
      settings_service: nil,
      layout_metrics: nil,
      terminal_service: nil,
      ui_component_factory: ui_factory,
      dictionary_ui_session: dictionary_ui_session,
      logger: nil,
      input_controller: input_controller,
      layout_service: nil,
      reader_controller: reader_controller,
      ui_controller: nil,
      clock: clock
    )
  end

  subject(:session) do
    described_class.new(dependencies: deps_bundle)
  end

  def setup_state
    popup.instance_variable_get(:@setup_state)
  end

  def lookup_result(query:, source:, target:)
    entry = Shoko::Core::Models::DictionaryEntry.new(word: query, senses: ['definition'])
    Shoko::Core::Models::DictionaryResult.new(
      query: query, entries: [entry], source_lang: source, target_lang: target, search_mode: :grouped
    )
  end

  describe '#begin_lookup' do
    it 'opens the install wizard when no usable pair exists' do
      session.begin_lookup(query: 'Haus')

      expect(popup).to be_setup_mode
      expect(setup_state[:stage]).to eq(:prompt_target)
      expect(setup_state[:source_lang]).to eq('en')
      expect(input_controller).to have_received(:enter_modal_mode).with(:dictionary)
    end

    context 'when a usable pair is available' do
      let(:available_pairs) { [{ source: 'en', target: 'de' }] }

      it 'looks the word up directly instead of starting the wizard' do
        allow(config_reader).to receive(:dictionary_target_lang).and_return('de')
        allow(dictionary_service).to receive(:lookup)
          .and_return(lookup_result(query: 'Haus', source: 'en', target: 'de'))

        session.begin_lookup(query: 'Haus')

        expect(dictionary_service).to have_received(:lookup).with('Haus', source_lang: 'en', target_lang: 'de')
        expect(popup).not_to be_setup_mode
      end
    end
  end

  describe '#resolve_pair' do
    let(:available_pairs) { [{ source: 'en', target: 'de' }] }

    it 'reports the resolved pair and the catalog of available pairs' do
      allow(config_reader).to receive(:dictionary_target_lang).and_return('de')

      pair = session.resolve_pair

      expect(pair).to include(source: 'en', target: 'de', available: true)
      expect(pair[:available_pairs]).to eq([{ source: 'en', target: 'de' }])
    end
  end

  describe '#handle_submit' do
    it 'advances from the source prompt to the target prompt' do
      allow(document).to receive(:metadata).and_return({})
      session.begin_lookup(query: 'Haus')
      expect(setup_state[:stage]).to eq(:prompt_source)

      session.handle_submit(stage: :prompt_source, value: 'en')

      expect(setup_state[:stage]).to eq(:prompt_target)
      expect(setup_state[:source_lang]).to eq('en')
    end
  end

  describe '#clear' do
    it 'forgets the in-flight wizard so the next result presents cleanly' do
      allow(document).to receive(:metadata).and_return({})
      session.begin_lookup(query: 'Haus')
      expect(popup).to be_setup_mode

      session.clear
      session.present_result(lookup_result(query: 'Haus', source: 'en', target: 'en'), announce: false)

      expect(popup).not_to be_setup_mode
    end
  end
end
