# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::DownloadWorkflow do
  class DownloadWorkflowTestCatalogRefreshControl
    include Shoko::Core::Ports::Outbound::CatalogRefreshControl

    attr_reader :calls

    def initialize
      @calls = []
    end

    def refresh_catalog(force:)
      @calls << { force: force }
    end
  end

  class DownloadWorkflowTestMenuSessionStore
    include Shoko::Core::Ports::Outbound::MenuSessionStore

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

  class DownloadWorkflowTestAppConfigStore
    include Shoko::Core::Ports::Outbound::AppConfigStore

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

  let(:download_service) { instance_double('DownloadService') }
  let(:menu_session_store) { DownloadWorkflowTestMenuSessionStore.new(Shoko::Core::Models::Session::MenuSnapshot.build) }
  let(:app_config_store) do
    DownloadWorkflowTestAppConfigStore.new(
      Shoko::Core::Models::Session::ConfigSnapshot.build(download_source: :gutendex)
    )
  end
  let(:catalog_refresh_control) { DownloadWorkflowTestCatalogRefreshControl.new }

  subject(:workflow) do
    described_class.new(
      download_service: download_service,
      app_config_store: app_config_store,
      menu_session_store: menu_session_store,
      catalog_refresh_control: catalog_refresh_control
    )
  end

  it 'requires catalog_refresh_control' do
    expect do
      described_class.new(
        download_service: download_service,
        app_config_store: app_config_store,
        menu_session_store: menu_session_store,
        catalog_refresh_control: nil
      )
    end.to raise_error(ArgumentError, 'catalog_refresh_control is required')
  end

  describe '#download_book' do
    let(:book) { { title: 'Pride and Prejudice' } }

    it 'refreshes catalog scan through runtime bridge after successful download' do
      allow(download_service).to receive(:download) do |_book, **_kwargs, &block|
        block&.call(1, 1)
        { path: '/tmp/books/pride.epub', existing: false }
      end

      workflow.download_book(book)

      expect(download_service).to have_received(:download).with(book, source: :gutendex)
      expect(catalog_refresh_control.calls).to eq([{ force: true }])
      expect(menu_session_store.load.download_status).to eq(:done)
      expect(menu_session_store.load.download_message).to eq('Saved to /tmp/books/pride.epub')
    end

    it 'raises a fatal external input error for malformed download payloads' do
      expect { workflow.download_book({ title: '   ' }) }
        .to raise_error(Shoko::FatalExternalInputError, 'download payload missing title')
    end
  end

  describe '#search_downloads' do
    it 'searches using the currently configured source' do
      allow(download_service).to receive(:search).with(query: 'austen', source: :libgen, page_url: nil).and_return(
        count: 1,
        next: nil,
        previous: nil,
        books: [{ title: 'Emma', source: :libgen }],
      )
      app_config_store.save(Shoko::Core::Models::Session::ConfigSnapshot.build(download_source: :libgen))

      workflow.search_downloads(query: 'austen')

      expect(download_service).to have_received(:search).with(query: 'austen', source: :libgen, page_url: nil)
      expect(menu_session_store.load.download_results).to eq([{ title: 'Emma', source: :libgen }])
      expect(menu_session_store.load.download_message).to eq('Found 1 of 1 on Libgen')
    end

    it 'shows a direct validation message for short libgen queries' do
      app_config_store.save(Shoko::Core::Models::Session::ConfigSnapshot.build(download_source: :libgen))
      allow(download_service).to receive(:search)

      workflow.search_downloads(query: 'ab')

      expect(download_service).not_to have_received(:search)
      expect(menu_session_store.load.download_status).to eq(:error)
      expect(menu_session_store.load.download_message).to eq('Libgen search needs at least 3 characters')
    end
  end
end
