# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::ReaderLaunch::RuntimeExecution do
  class ReaderLaunchRuntimeExecutionTestMenuSessionStore
    include Shoko::Application::Ports::Outbound::MenuSessionStore

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

  class ReaderLaunchRuntimeExecutionTestReaderSessionStore
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

  let(:menu_session_store) do
    ReaderLaunchRuntimeExecutionTestMenuSessionStore.new(
      Shoko::Application::Ports::Outbound::State::MenuSessionSnapshot.build(mode: :browse)
    )
  end
  let(:reader_session_store) do
    ReaderLaunchRuntimeExecutionTestReaderSessionStore.new(Shoko::Application::Ports::Outbound::State::ReaderSnapshot.build)
  end
  let(:reader_launch_state) do
    Shoko::Adapters::Runtime::SessionState::ReaderLaunchStateAdapter.new.tap do |state|
      state.preloaded_document = instance_double('Document')
      state.background_worker = instance_double('BackgroundWorker')
    end
  end
  let(:menu_launch_state) { Shoko::Adapters::Runtime::SessionState::MenuLaunchStateAdapter.new }
  let(:recent_files_repository) { instance_double('RecentFilesRepository', add: nil) }
  let(:catalog) { instance_double('Catalog', update_scan_state: nil) }
  let(:menu_runtime) { instance_double('MenuRuntime', run_reader: nil, switch_mode: nil) }
  let(:path_resolution) do
    instance_double(
      'PathResolution',
      canonical_path: '/books/a.epub',
      canonical_recent_path: '/books/a.epub'
    )
  end
  let(:logger) { instance_double('Logger', debug: nil, error: nil, respond_to?: true) }

  subject(:service) do
    described_class.new(
      deps: described_class::Dependencies.new(
        menu_session_store: menu_session_store,
        reader_session_store: reader_session_store,
        reader_launch_state: reader_launch_state,
        menu_launch_state: menu_launch_state,
        recent_files_repository: recent_files_repository,
        catalog: catalog,
        menu_runtime: menu_runtime,
        path_resolution: path_resolution,
        logger: logger
      ).validate!
    )
  end

  it 'runs reader and restores menu mode on completion' do
    ensure_callback = ->(_path) { true }
    preloaded_document = reader_launch_state.preloaded_document
    background_worker = reader_launch_state.background_worker

    service.run_reader(path: '/tmp/a.epub', ensure_reader_document_for: ensure_callback)

    expect(reader_session_store.load.book_path).to eq('/books/a.epub')
    expect(reader_session_store.load.running).to be(true)
    expect(reader_session_store.load.mode).to eq(:read)
    expect(menu_runtime).to have_received(:run_reader).with(
      path: '/books/a.epub',
      preloaded_document: preloaded_document,
      background_worker: background_worker
    )
    expect(menu_runtime).to have_received(:switch_mode).with(:browse)
    expect(reader_launch_state.preloaded_document).to be_nil
    expect(reader_launch_state.background_worker).to be_nil
  end
end
