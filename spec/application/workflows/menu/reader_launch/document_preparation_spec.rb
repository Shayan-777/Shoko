# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::ReaderLaunch::DocumentPreparation do
  class ReaderLaunchDocumentPreparationTestReaderSessionStore
    include Shoko::Core::Ports::Outbound::ReaderSessionStore

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

  let(:reader_launch_state) { Shoko::Adapters::Runtime::SessionState::ReaderLaunchStateAdapter.new }
  let(:reader_session_store) do
    ReaderLaunchDocumentPreparationTestReaderSessionStore.new(Shoko::Core::Models::Session::ReaderSnapshot.build)
  end
  let(:logger) { instance_double('Logger', debug: nil) }
  let(:loaded_document) { instance_double('Document', chapter_count: 7, canonical_path: '/books/a.epub') }
  let(:document_loader) do
    Class.new do
      include Shoko::Core::Ports::Outbound::DocumentLoader

      def load(path:, progress_reporter: nil, background_worker: nil)
      end
    end.new
  end
  let(:background_worker_builder) do
    Class.new do
      include Shoko::Core::Ports::Outbound::BackgroundWorkerBuilder

      def build(name:, logger:)
      end
    end.new
  end
  let(:path_resolution) do
    instance_double(
      'PathResolution',
      canonical_path: '/books/a.epub',
      document_matches?: false,
      cache_pointer?: false
    )
  end

  subject(:service) do
    described_class.new(
      deps: described_class::Dependencies.new(
        document_loader: document_loader,
        reader_launch_state: reader_launch_state,
        reader_session_store: reader_session_store,
        background_worker_builder: background_worker_builder,
        logger: logger
      ).validate!
    )
  end

  it 'loads and registers reader document when canonical path differs' do
    allow(document_loader).to receive(:load)
      .with(path: '/books/a.epub', progress_reporter: nil, background_worker: nil)
      .and_return(loaded_document)

    result = service.ensure_reader_document_for(
      path: '/tmp/a.epub',
      path_resolution: path_resolution,
      on_error: nil
    )

    expect(result).to be(true)
    expect(reader_launch_state.preloaded_document).to eq(loaded_document)
    expect(reader_session_store.load.total_chapters).to eq(7)
  end

  it 'reuses current document when canonical path already matches' do
    reader_launch_state.set_preloaded_document(loaded_document)
    allow(path_resolution).to receive(:document_matches?).with(loaded_document, '/books/a.epub').and_return(true)
    allow(document_loader).to receive(:load)

    result = service.ensure_reader_document_for(
      path: '/tmp/a.epub',
      path_resolution: path_resolution,
      on_error: nil
    )

    expect(result).to be(true)
    expect(document_loader).not_to have_received(:load)
  end
end
