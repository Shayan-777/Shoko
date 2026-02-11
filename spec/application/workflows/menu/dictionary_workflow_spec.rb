# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::DictionaryWorkflow do
  let(:dictionary_catalog_service) { instance_double('DictionaryCatalogService') }
  let(:dictionary_storage) { instance_double('DictionaryStorage', ensure_databases_path: '/tmp/shoko/dictionary') }
  let(:config_reader) { instance_double('ConfigReader', dictionary_path: nil) }
  let(:menu_state_reader) { instance_double('MenuStateReader', dictionary_results: []) }
  let(:menu_state_writer) { instance_double('MenuStateWriter', update_menu: nil) }
  let(:draw_screen) { instance_double('DrawScreen', call: nil) }
  let(:clock) { instance_double('Clock', monotonic_now: 1.0) }

  subject(:workflow) do
    described_class.new(
      dictionary_catalog_service: dictionary_catalog_service,
      dictionary_storage: dictionary_storage,
      config_reader: config_reader,
      menu_state_reader: menu_state_reader,
      menu_state_writer: menu_state_writer,
      draw_screen: -> { draw_screen.call },
      clock: clock
    )
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
    end
  end
end
