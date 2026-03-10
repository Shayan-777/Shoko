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

  let(:download_service) { instance_double('DownloadService') }
  let(:menu_session_store) { DownloadWorkflowTestMenuSessionStore.new(Shoko::Core::Models::Session::MenuSnapshot.build) }
  let(:catalog_refresh_control) { DownloadWorkflowTestCatalogRefreshControl.new }

  subject(:workflow) do
    described_class.new(
      download_service: download_service,
      menu_session_store: menu_session_store,
      catalog_refresh_control: catalog_refresh_control
    )
  end

  it 'requires catalog_refresh_control' do
    expect do
      described_class.new(
        download_service: download_service,
        menu_session_store: menu_session_store,
        catalog_refresh_control: nil
      )
    end.to raise_error(ArgumentError, 'catalog_refresh_control is required')
  end

  describe '#download_book' do
    let(:book) { { title: 'Pride and Prejudice' } }

    it 'refreshes catalog scan through runtime bridge after successful download' do
      allow(download_service).to receive(:download) do |_book, &block|
        block&.call(1, 1)
        { path: '/tmp/books/pride.epub', existing: false }
      end

      workflow.download_book(book)

      expect(download_service).to have_received(:download).with(book)
      expect(catalog_refresh_control.calls).to eq([{ force: true }])
      expect(menu_session_store.load.download_status).to eq(:done)
      expect(menu_session_store.load.download_message).to eq('Saved to /tmp/books/pride.epub')
    end

    it 'raises a fatal external input error for malformed download payloads' do
      expect { workflow.download_book({ title: '   ' }) }
        .to raise_error(Shoko::FatalExternalInputError, 'download payload missing title')
    end
  end
end
