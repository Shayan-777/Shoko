# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::ReaderLaunch::DocumentPreparation do
  class ReaderLaunchDocumentPreparationTestReaderSessionStore
    include Shoko::Application::Ports::Outbound::ReaderSessionStore

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
    ReaderLaunchDocumentPreparationTestReaderSessionStore.new(Shoko::Application::Ports::Outbound::State::ReaderSnapshot.build)
  end
  let(:logger) { instance_double(Shoko::Application::Ports::Outbound::Logging, debug: nil) }
  let(:loaded_document) { instance_double(Shoko::Application::Models::ReaderDocument, chapter_count: 7, canonical_path: '/books/a.epub') }
  let(:document_loader) do
    Class.new do
      include Shoko::Application::Ports::Outbound::DocumentLoader

      def load(path:, progress_reporter: nil)
      end
    end.new
  end
  let(:background_worker_builder) do
    Class.new do
      include Shoko::Application::Ports::Outbound::BackgroundWorkerBuilder

      def build(name:, logger:)
      end
    end.new
  end
  let(:path_resolution) do
    instance_double(
      Shoko::Application::Workflows::Menu::ReaderLaunch::Contracts::PathResolution,
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
      .with(path: '/books/a.epub', progress_reporter: nil)
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

  it 'resets an out-of-range current_chapter when switching to a smaller book' do
    # Simulates reading deep into a long book, then opening a shorter one:
    # the stale current_chapter must not exceed the new total_chapters.
    reader_session_store.save(reader_session_store.load.with(current_chapter: 21, total_chapters: 30))
    smaller_document = instance_double(Shoko::Application::Models::ReaderDocument, chapter_count: 16, canonical_path: '/books/a.epub')
    allow(document_loader).to receive(:load).and_return(smaller_document)

    result = service.ensure_reader_document_for(
      path: '/tmp/a.epub',
      path_resolution: path_resolution,
      on_error: nil
    )

    expect(result).to be(true)
    expect(reader_session_store.load.total_chapters).to eq(16)
    expect(reader_session_store.load.current_chapter).to eq(0)
  end

  it 'preserves an in-range current_chapter when switching books' do
    reader_session_store.save(reader_session_store.load.with(current_chapter: 5, total_chapters: 30))
    allow(document_loader).to receive(:load).and_return(loaded_document) # chapter_count: 7

    service.ensure_reader_document_for(
      path: '/tmp/a.epub',
      path_resolution: path_resolution,
      on_error: nil
    )

    expect(reader_session_store.load.total_chapters).to eq(7)
    expect(reader_session_store.load.current_chapter).to eq(5)
  end

  it 'reuses current document when canonical path already matches' do
    reader_launch_state.preloaded_document = loaded_document
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
