# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::DictionaryController do
  class FakeDictionaryUiFactory
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
  let(:lookup_card) { instance_double('DictionaryLookupCard') }
  let(:ui_factory) { FakeDictionaryUiFactory.new(popup) }
  let(:book_path) { '/books/book-a.epub' }
  let(:reader_state) do
    instance_double(
      'ReaderState',
      selection: nil,
      dictionary_lookup_popup: lookup_card,
      dictionary_popup: popup,
      dictionary_query: 'Haus',
      mode: :dictionary,
      book_path: book_path
    )
  end
  let(:config_reader) do
    instance_double(
      'ConfigReader',
      dictionary_source_lang: 'auto',
      dictionary_target_lang: 'en',
      dictionary_path: nil,
      view_mode: :single
    )
  end
  let(:reader_session_mutator) do
    instance_double('ReaderSessionMutator',
                    update_reader: nil,
                    clear_selection: nil,
                    update_config: nil)
  end
  let(:dictionary_service) do
    instance_double(
      'DictionaryService',
      configured_source_lang: 'de',
      configured_target_lang: 'en',
      available_language_pairs: [],
      language_pair_available?: false
    )
  end
  let(:terminal_service) { instance_double('TerminalService', size: [24, 80]) }
  let(:input_controller) { instance_double('InputController', enter_modal_mode: nil, exit_modal_mode: nil) }
  let(:selection_service) { instance_double('SelectionService', extract_text: 'Haus') }
  let(:rendered_content_reader) { instance_double('RenderedContentReader', rendered_lines: {}) }
  let(:reader_controller) do
    instance_double('ReaderController', draw_screen: nil, render_coordinator: nil, rebuild_root_layout: nil)
  end
  let(:dictionary_catalog_service) { instance_double('DictionaryCatalogService') }
  let(:dictionary_availability) { instance_double('DictionaryAvailability', sqlite3_available?: true) }
  let(:dictionary_storage) { instance_double('DictionaryStorage', ensure_databases_path: '/tmp/shoko-dict') }
  let(:notification_service) { instance_double('NotificationService', set_message: nil) }
  let(:clock) { instance_double('Clock', monotonic_now: 1.0) }
  let(:document_metadata) { { language: 'en_US' } }
  let(:document) { instance_double('Document', metadata: document_metadata, source_path: book_path, language: 'en_US') }
  let(:dictionary_ui_session) do
    Shoko::Adapters::Ui::Sessions::DictionaryUiSessionAdapter.new(
      reader_state_reader: reader_state,
      reader_session_mutator: reader_session_mutator,
      ui_component_factory: ui_factory
    )
  end

  subject(:controller) do
    deps = described_class::Dependencies.build(
      reader_state: reader_state,
      config_reader: config_reader,
      reader_session_mutator: reader_session_mutator,
      layout_metrics: nil,
      dictionary_service: dictionary_service,
      dictionary_catalog_service: dictionary_catalog_service,
      dictionary_availability: dictionary_availability,
      dictionary_storage: dictionary_storage,
      terminal_service: terminal_service,
      ui_component_factory: ui_factory,
      logger: nil,
      input_controller: input_controller,
      layout_service: nil,
      reader_controller: reader_controller,
      document: document,
      selection_service: selection_service,
      rendered_content_reader: rendered_content_reader,
      notification_service: notification_service,
      settings_service: nil,
      ui_controller: nil,
      clock: clock,
      dictionary_ui_session: dictionary_ui_session
    ).validate!
    described_class.new(deps: deps)
  end

  def lookup_action
    {
      action: :lookup,
      data: {
        selection_range: {
          start: { page_id: 0, geometry_key: 'a', line_offset: 0, cell_index: 0, row: 1, column_origin: 1 },
          end: { page_id: 0, geometry_key: 'a', line_offset: 0, cell_index: 4, row: 1, column_origin: 1 },
        },
      },
    }
  end

  def setup_state
    popup.instance_variable_get(:@setup_state)
  end

  def lookup_result(query:, source:, target:)
    entry = Shoko::Core::Models::DictionaryEntry.new(word: query, senses: ['definition'])
    Shoko::Core::Models::DictionaryResult.new(
      query: query,
      entries: [entry],
      source_lang: source,
      target_lang: target,
      search_mode: :grouped
    )
  end

  # The "Define" bar writes the query to view-state, then submits; drive the
  # setup flow directly from a settled query (the bar would do this on Enter).
  def start_lookup(word: 'Haus')
    allow(reader_state).to receive(:dictionary_query).and_return(word)
    controller.submit_dictionary_lookup
  end

  describe 'opening the define bar' do
    it 'opens an empty bar on the hotkey and enters dictionary mode' do
      allow(reader_state).to receive(:dictionary_query).and_return('')

      controller.open_dictionary_lookup(nil)

      expect(input_controller).to have_received(:enter_modal_mode).with(:dictionary)
      expect(reader_session_mutator).to have_received(:update_reader)
        .with(hash_including(mode: :dictionary, dictionary_query: ''))
    end

    it 'pre-fills the query from a selection payload' do
      controller.open_dictionary_lookup(lookup_action)

      expect(reader_session_mutator).to have_received(:update_reader)
        .with(hash_including(dictionary_query: 'Haus'))
    end
  end

  describe 'setup flow' do
    before do
      allow(dictionary_catalog_service).to receive(:list_remote).and_return([])
      allow(dictionary_catalog_service).to receive(:download).and_return(path: '/tmp/en-de.sqlite3', existing: false)
      allow(dictionary_service).to receive(:lookup).and_return(lookup_result(query: 'Haus', source: 'en', target: 'en'))
    end

    it 'uses metadata language and starts at target prompt when source is known' do
      start_lookup

      expect(popup).to be_setup_mode
      expect(setup_state[:stage]).to eq(:prompt_target)
      expect(setup_state[:source_lang]).to eq('en')
    end

    it 'prompts for source language when metadata language is missing' do
      allow(document).to receive(:metadata).and_return({})

      start_lookup

      expect(popup).to be_setup_mode
      expect(setup_state[:stage]).to eq(:prompt_source)
    end

    it 'validates manual source language input' do
      allow(document).to receive(:metadata).and_return({})
      start_lookup

      controller.dictionary_confirm

      expect(popup).to be_setup_mode
      expect(setup_state[:stage]).to eq(:prompt_source)
      expect(setup_state[:status]).to include('valid source language')
    end

    it 'prompts for target language each setup invocation' do
      start_lookup
      first_stage = setup_state[:stage]

      start_lookup
      second_stage = setup_state[:stage]

      expect(first_stage).to eq(:prompt_target)
      expect(second_stage).to eq(:prompt_target)
    end

    it 'supports suggestion selection and tab apply in setup' do
      allow(config_reader).to receive(:dictionary_target_lang).and_return('de')

      start_lookup
      expect(setup_state[:suggestions]).not_to be_empty

      controller.dictionary_scroll_down
      selected_index = setup_state[:suggestion_index]
      selected_code = setup_state[:suggestions][selected_index][:code]

      controller.dictionary_tab

      expect(setup_state[:input_value]).to eq(selected_code)
    end

    it 'supports swapping source and target with S in target stage' do
      allow(config_reader).to receive(:dictionary_target_lang).and_return('de')

      start_lookup
      expect(setup_state[:source_lang]).to eq('en')

      controller.dictionary_swap_languages

      expect(setup_state[:stage]).to eq(:prompt_target)
      expect(setup_state[:source_lang]).to eq('de')
      expect(setup_state[:input_value]).to eq('en')
    end

    it 'auto-downloads exact pair and performs lookup' do
      allow(config_reader).to receive(:dictionary_target_lang).and_return('de')
      allow(dictionary_catalog_service).to receive(:list_remote).and_return(
        [{ source: 'en', target: 'de', name: 'en-de.sqlite3' }]
      )
      allow(dictionary_service).to receive(:lookup).and_return(lookup_result(query: 'Haus', source: 'en', target: 'de'))

      start_lookup
      controller.dictionary_confirm

      expect(dictionary_storage).to have_received(:ensure_databases_path).with(nil)
      expect(dictionary_catalog_service).to have_received(:download)
      expect(dictionary_service).to have_received(:lookup).with('Haus', source_lang: 'en', target_lang: 'de')
      expect(popup).not_to be_setup_mode
    end

    it 'normalizes language names entered in setup before catalog matching' do
      allow(document).to receive(:metadata).and_return({})
      allow(config_reader).to receive(:dictionary_target_lang).and_return('de')
      allow(dictionary_catalog_service).to receive(:list_remote).and_return(
        [{ source: 'en', target: 'de', name: 'en-de.sqlite3' }]
      )
      allow(dictionary_service).to receive(:lookup).and_return(lookup_result(query: 'Haus', source: 'en', target: 'de'))

      start_lookup
      'english'.each_char { |ch| controller.dictionary_insert_char(ch) }
      controller.dictionary_confirm
      controller.dictionary_confirm

      expect(dictionary_storage).to have_received(:ensure_databases_path).with(nil)
      expect(dictionary_catalog_service).to have_received(:download)
      expect(dictionary_service).to have_received(:lookup).with('Haus', source_lang: 'en', target_lang: 'de')
    end

    it 'shows an error when exact pair is missing from catalog' do
      allow(config_reader).to receive(:dictionary_target_lang).and_return('de')
      allow(dictionary_catalog_service).to receive(:list_remote).and_return(
        [{ source: 'en', target: 'fr', name: 'en-fr.sqlite3' }]
      )

      start_lookup
      controller.dictionary_confirm

      expect(popup).to be_setup_mode
      expect(setup_state[:status]).to include('No dictionary dataset found')
    end

    it 'shows download errors inside setup popup' do
      allow(config_reader).to receive(:dictionary_target_lang).and_return('de')
      allow(dictionary_catalog_service).to receive(:list_remote)
        .and_raise(Shoko::Adapters::Storage::DictionaryCatalogService::CatalogError, 'network down')

      start_lookup
      controller.dictionary_confirm

      expect(popup).to be_setup_mode
      expect(setup_state[:status]).to include('Download failed: network down')
    end

    it 'remembers manual source per book only' do
      current_book = '/books/book-a.epub'
      allow(reader_state).to receive(:book_path) { current_book }
      allow(document).to receive(:metadata).and_return({})

      start_lookup
      controller.dictionary_insert_char('e')
      controller.dictionary_insert_char('n')
      controller.dictionary_confirm
      expect(setup_state[:stage]).to eq(:prompt_target)

      controller.close_dictionary_lookup
      start_lookup
      expect(setup_state[:stage]).to eq(:prompt_target)

      current_book = '/books/book-b.epub'
      controller.close_dictionary_lookup
      start_lookup
      expect(setup_state[:stage]).to eq(:prompt_source)
    end
  end
end
