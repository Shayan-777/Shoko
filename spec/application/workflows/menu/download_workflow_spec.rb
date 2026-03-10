# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::DownloadWorkflow do
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
  let(:menu_runtime) { instance_spy('MenuRuntime', draw_screen: nil, refresh_scan: nil) }
  let(:clock) { instance_double('Clock', monotonic_now: 1.0) }

  before do
    allow(menu_runtime).to receive(:is_a?).and_return(false)
    allow(menu_runtime).to receive(:is_a?)
      .with(Shoko::Core::Ports::Outbound::MenuWorkflowRuntime)
      .and_return(true)
  end

  subject(:workflow) do
    described_class.new(
      download_service: download_service,
      menu_session_store: menu_session_store,
      menu_runtime: menu_runtime,
      clock: clock
    )
  end

  it 'requires menu_runtime' do
    expect do
      described_class.new(
        download_service: download_service,
        menu_session_store: menu_session_store,
        menu_runtime: nil,
        clock: clock
      )
    end.to raise_error(ArgumentError, 'menu_runtime is required')
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
      expect(menu_runtime).to have_received(:refresh_scan).with(force: true)
      expect(menu_session_store.load.download_status).to eq(:done)
      expect(menu_session_store.load.download_message).to eq('Saved to /tmp/books/pride.epub')
    end

    it 'raises a fatal external input error for malformed download payloads' do
      expect { workflow.download_book({ title: '   ' }) }
        .to raise_error(Shoko::FatalExternalInputError, 'download payload missing title')
    end
  end
end
