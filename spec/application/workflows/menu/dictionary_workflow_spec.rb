# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::DictionaryWorkflow do
  class PortMenuWorkflowStateReaderDouble
    include Shoko::Core::Ports::Outbound::MenuWorkflowStateReader

    attr_accessor :dictionary_entries_value

    def initialize
      @dictionary_entries_value = []
    end

    def current_menu_mode
      :browse
    end

    def selected_library_index
      0
    end

    def selected_annotation_record
      nil
    end

    def selected_annotation_book_path
      nil
    end

    def annotation_editor_text
      ''
    end

    def dictionary_entries
      @dictionary_entries_value
    end
  end

  class PortMenuWorkflowStateWriterDouble
    include Shoko::Core::Ports::Outbound::MenuWorkflowStateWriter

    def set_download_state(_attrs); end
    def set_dictionary_state(_attrs); end
    def set_annotation_state(_attrs); end
    def set_loading_state(path: nil, active: nil, progress: nil, message: nil, index: nil, mode: nil); end
  end

  let(:dictionary_catalog_service) { instance_double('DictionaryCatalogService') }
  let(:dictionary_storage) { instance_double('DictionaryStorage', ensure_databases_path: '/tmp/shoko/dictionary') }
  let(:config_reader) { instance_double('ConfigReader', dictionary_path: nil) }
  let(:menu_state_reader) { PortMenuWorkflowStateReaderDouble.new }
  let(:menu_state_writer) { instance_spy(PortMenuWorkflowStateWriterDouble) }
  let(:menu_runtime) { instance_spy('MenuRuntime', draw_screen: nil, refresh_scan: nil) }
  let(:clock) { instance_double('Clock', monotonic_now: 1.0) }

  before do
    allow(menu_state_writer).to receive(:is_a?).and_return(false)
    allow(menu_state_writer).to receive(:is_a?)
      .with(Shoko::Core::Ports::Outbound::MenuWorkflowStateWriter)
      .and_return(true)

    allow(menu_runtime).to receive(:is_a?).and_return(false)
    allow(menu_runtime).to receive(:is_a?)
      .with(Shoko::Core::Ports::Outbound::MenuWorkflowRuntime)
      .and_return(true)
  end

  subject(:workflow) do
    described_class.new(
      dictionary_catalog_service: dictionary_catalog_service,
      dictionary_storage: dictionary_storage,
      config_reader: config_reader,
      menu_state_reader: menu_state_reader,
      menu_state_writer: menu_state_writer,
      menu_runtime: menu_runtime,
      clock: clock
    )
  end

  it 'requires menu_runtime' do
    expect do
      described_class.new(
        dictionary_catalog_service: dictionary_catalog_service,
        dictionary_storage: dictionary_storage,
        config_reader: config_reader,
        menu_state_reader: menu_state_reader,
        menu_state_writer: menu_state_writer,
        menu_runtime: nil,
        clock: clock
      )
    end.to raise_error(ArgumentError, 'menu_runtime is required')
  end

  describe '#download_dictionary' do
    let(:entry) { { source: 'en', target: 'de', name: 'en-de.sqlite3' } }

    it 'uses dictionary_storage.ensure_databases_path as download destination' do
      allow(dictionary_catalog_service).to receive(:download) do |_entry, _dest, &block|
        block&.call(1, 1)
        { path: '/tmp/shoko/dictionary/en-de.sqlite3', existing: false }
      end

      workflow.download_dictionary(entry)

      expect(dictionary_storage).to have_received(:ensure_databases_path).with(nil)
      expect(dictionary_catalog_service).to have_received(:download).with(entry, '/tmp/shoko/dictionary')
      expect(menu_state_writer).to have_received(:set_dictionary_state).at_least(:once)
    end
  end
end
