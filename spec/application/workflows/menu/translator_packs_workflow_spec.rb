# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::TranslatorPacksWorkflow do
  class TranslatorPacksTestMenuSessionStore
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

  class TranslatorPacksTestMenuTransientStore
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

  def remote_pack(from, to, version: '1.0', size: 100)
    Shoko::Adapters::Translation::ModelCatalogService::RemotePack.new(
      from: from, to: to, version: version,
      model: Shoko::Adapters::Translation::ModelCatalogService::RemoteFile.new(
        name: "model.#{from}#{to}.bin", url: 'https://cdn/m.bin', size: size - 10, sha256: ''
      ),
      vocab: Shoko::Adapters::Translation::ModelCatalogService::RemoteFile.new(
        name: "vocab.#{from}#{to}.spm", url: 'https://cdn/v.spm', size: 10, sha256: ''
      )
    )
  end

  def installed_pack(from, to)
    Shoko::Adapters::Translation::ModelStore::InstalledPack.new(
      from: from, to: to, dir: "/packs/#{from}-#{to}",
      model_path: '/m.bin', vocab_path: '/v.spm', version: '1.0'
    )
  end

  let(:model_catalog_service) { instance_double(Shoko::Adapters::Translation::ModelCatalogService) }
  let(:model_store) { instance_double(Shoko::Adapters::Translation::ModelStore) }
  let(:menu_session_store) do
    TranslatorPacksTestMenuSessionStore.new(Shoko::Application::Ports::Outbound::State::MenuSessionSnapshot.build)
  end
  let(:menu_transient_store) do
    TranslatorPacksTestMenuTransientStore.new(
      Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot.build(translator_packs_results: [])
    )
  end

  subject(:workflow) do
    described_class.new(
      model_catalog_service: model_catalog_service,
      model_store: model_store,
      menu_session_store: menu_session_store,
      menu_transient_store: menu_transient_store
    )
  end

  def transient
    menu_transient_store.snapshot
  end

  describe '#fetch_pack_catalog' do
    it 'stores the catalog with installation flags' do
      allow(model_catalog_service).to receive(:list_remote)
        .and_return([remote_pack('et', 'en'), remote_pack('en', 'de')])
      allow(model_store).to receive(:installed_packs).and_return([installed_pack('et', 'en')])

      workflow.fetch_pack_catalog

      expect(transient.translator_packs_status).to eq(:done)
      results = transient.translator_packs_results
      expect(results.length).to eq(2)
      expect(results.find { |r| r[:from] == 'et' }[:installed]).to be(true)
      expect(results.find { |r| r[:from] == 'en' }[:installed]).to be(false)
    end

    it 'degrades to an error status when the catalog fails' do
      allow(model_catalog_service).to receive(:list_remote)
        .and_raise(Shoko::Adapters::Translation::ModelCatalogService::CatalogError, 'offline')

      workflow.fetch_pack_catalog

      expect(transient.translator_packs_status).to eq(:error)
      expect(transient.translator_packs_message).to include('offline')
    end
  end

  describe '#download_pack' do
    it 'downloads an uninstalled pack, reports progress, and marks it installed' do
      remote = remote_pack('et', 'en')
      allow(model_catalog_service).to receive(:list_remote).and_return([remote])
      allow(model_store).to receive(:installed_packs).and_return([])
      workflow.fetch_pack_catalog

      allow(model_catalog_service).to receive(:download) do |_pack, _store, &block|
        block.call(50, 100)
        block.call(100, 100)
      end

      workflow.download_pack(transient.translator_packs_results.first)

      expect(model_catalog_service).to have_received(:download)
        .with(remote, model_store)
      expect(transient.translator_packs_status).to eq(:done)
      expect(transient.translator_packs_message).to include('Installed')
      expect(transient.translator_packs_results.first[:installed]).to be(true)
    end

    it 'removes an installed pack instead of re-downloading it' do
      allow(model_catalog_service).to receive(:list_remote).and_return([remote_pack('et', 'en')])
      allow(model_store).to receive(:installed_packs).and_return([installed_pack('et', 'en')])
      workflow.fetch_pack_catalog

      allow(model_store).to receive(:remove)
      workflow.download_pack(transient.translator_packs_results.first)

      expect(model_store).to have_received(:remove).with('et', 'en')
      expect(transient.translator_packs_message).to include('Removed')
      expect(transient.translator_packs_results.first[:installed]).to be(false)
    end

    it 'degrades to an error status when the download fails' do
      allow(model_catalog_service).to receive(:list_remote).and_return([remote_pack('et', 'en')])
      allow(model_store).to receive(:installed_packs).and_return([])
      workflow.fetch_pack_catalog

      allow(model_catalog_service).to receive(:download)
        .and_raise(Shoko::Adapters::Translation::ModelCatalogService::CatalogError, 'checksum mismatch')

      workflow.download_pack(transient.translator_packs_results.first)

      expect(transient.translator_packs_status).to eq(:error)
      expect(transient.translator_packs_message).to include('checksum mismatch')
    end

    it 'ignores nil entries' do
      expect { workflow.download_pack(nil) }.not_to raise_error
    end
  end
end
