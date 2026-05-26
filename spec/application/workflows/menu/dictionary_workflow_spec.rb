# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::DictionaryWorkflow do
  class DictionaryWorkflowTestConfigStore
    include Shoko::Application::Ports::Outbound::AppConfigStore

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

  class DictionaryWorkflowTestMenuSessionStore
    include Shoko::Application::Ports::Outbound::MenuSessionStore

    attr_reader :snapshot

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

  class DictionaryWorkflowTestMenuTransientStore
    include Shoko::Application::Ports::Outbound::MenuTransientStore

    attr_reader :snapshot

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

  let(:dictionary_catalog_service) { instance_double('DictionaryCatalogService') }
  let(:dictionary_storage) { instance_double('DictionaryStorage', ensure_databases_path: '/tmp/shoko/dictionary') }
  let(:app_config_store) do
    DictionaryWorkflowTestConfigStore.new(Shoko::Core::Models::Session::ConfigSnapshot.build(dictionary_path: nil))
  end
  let(:menu_session_store) do
    DictionaryWorkflowTestMenuSessionStore.new(Shoko::Core::Models::Session::MenuSessionSnapshot.build)
  end
  let(:menu_transient_store) do
    DictionaryWorkflowTestMenuTransientStore.new(
      Shoko::Core::Models::Session::MenuTransientSnapshot.build(dictionary_results: [])
    )
  end

  subject(:workflow) do
    described_class.new(
      dictionary_catalog_service: dictionary_catalog_service,
      dictionary_storage: dictionary_storage,
      app_config_store: app_config_store,
      menu_session_store: menu_session_store,
      menu_transient_store: menu_transient_store
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
      expect(dictionary_catalog_service).to have_received(:download).with(
        hash_including(source: 'en', target: 'de', name: 'en-de.sqlite3'),
        '/tmp/shoko/dictionary'
      )
      expect(menu_transient_store.load.dictionary_status).to eq(:done)
      expect(menu_transient_store.load.dictionary_message).to eq('Saved to /tmp/shoko/dictionary/en-de.sqlite3')
    end
  end
end
