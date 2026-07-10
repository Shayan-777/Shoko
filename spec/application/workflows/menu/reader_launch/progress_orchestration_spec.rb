# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::ReaderLaunch::ProgressOrchestration do
  class ReaderLaunchProgressOrchestrationTestMenuSessionStore
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

  let(:menu_session_store) do
    ReaderLaunchProgressOrchestrationTestMenuSessionStore.new(
      Shoko::Application::Ports::Outbound::State::MenuSessionSnapshot.build(browse_selected: 0, mode: :browse)
    )
  end
  let(:progress_presenter) do
    instance_double(
      Shoko::Adapters::Runtime::SessionState::MenuProgressPresenter,
      show: nil,
      clear: nil,
      update_status: false,
      update_message: nil,
      update: nil
    )
  end
  let(:progress_presenters) { instance_double(Shoko::Application::Ports::Outbound::MenuProgressPresenters, build: progress_presenter) }
  let(:null_presenter) { instance_double(Shoko::Application::Workflows::Menu::NullProgressPresenter) }
  let(:pagination_runtime) { instance_double(Shoko::Application::Services::Pagination::PaginationRuntime, build_full_map: nil) }
  let(:pagination_orchestrator) { instance_double(Shoko::Application::Services::Pagination::PaginationOrchestrator, bind: pagination_runtime) }
  let(:page_calculator) { instance_double(Shoko::Application::Services::Pagination::PageCalculatorService) }
  let(:app_config_store) { instance_double(Shoko::Application::Ports::Outbound::AppConfigStore) }
  let(:reader_session_store) { instance_double(Shoko::Application::Ports::Outbound::ReaderSessionStore) }
  let(:reader_view_state_store) { instance_double(Shoko::Application::Ports::Outbound::ReaderViewStateStore) }
  let(:reader_pagination_store) { instance_double(Shoko::Application::Ports::Outbound::ReaderPaginationStore) }
  let(:reader_runtime_context) do
    instance_double(
      Shoko::Application::Ports::Outbound::ReaderRuntimeContext,
      terminal_size: Shoko::Application::Ports::Outbound::State::TerminalSize.build(width: 80, height: 24)
    )
  end

  subject(:service) do
    described_class.new(
      deps: described_class::Dependencies.new(
        menu_session_store: menu_session_store,
        progress_presenters: progress_presenters,
        null_presenter: null_presenter,
        pagination_orchestrator: pagination_orchestrator,
        page_calculator: page_calculator,
        app_config_store: app_config_store,
        reader_session_store: reader_session_store,
        reader_view_state_store: reader_view_state_store,
        reader_pagination_store: reader_pagination_store,
        pagination_cache_preloader: nil,
        runtime_config: nil,
        reader_runtime_context: reader_runtime_context,
        logger: nil
      ).validate!
    )
  end

  it 'runs launch flow with progress overlay and clears presenter' do
    prepare = lambda do |_path, presenter|
      expect(presenter).to eq(progress_presenter)
      nil
    end
    run_reader = double('RunReader', call: nil)

    service.load_and_open_with_progress(
      path: '/books/a.epub',
      prepare_reader_launch: prepare,
      run_reader: run_reader
    )

    expect(progress_presenter).to have_received(:show).with(path: '/books/a.epub', index: 0, mode: :browse)
    expect(progress_presenter).to have_received(:clear)
    expect(run_reader).to have_received(:call).with('/books/a.epub')
  end

  it 'keeps the overlay up until the reader returns, then clears it' do
    order = []
    allow(progress_presenter).to receive(:clear) { order << :clear }
    run_reader = ->(_path) { order << :run_reader }

    service.load_and_open_with_progress(
      path: '/books/a.epub',
      prepare_reader_launch: ->(_path, _presenter) {},
      run_reader: run_reader
    )

    expect(order).to eq(%i[run_reader clear])
  end

  it 'clears the overlay when the reader launch raises' do
    expect do
      service.load_and_open_with_progress(
        path: '/books/a.epub',
        prepare_reader_launch: ->(_path, _presenter) { raise Shoko::StateUpdateError, 'boom' },
        run_reader: ->(_path) {}
      )
    end.to raise_error(Shoko::StateUpdateError)

    expect(progress_presenter).to have_received(:clear)
  end

  it 'binds the full pagination runtime contract during pagination build' do
    document = instance_double(Shoko::Application::Models::ReaderDocument, cached?: false)

    expect(pagination_orchestrator).to receive(:bind).with(
      doc: document,
      page_calculator: page_calculator,
      app_config_store: app_config_store,
      reader_session_store: reader_session_store,
      reader_view_state_store: reader_view_state_store,
      reader_pagination_store: reader_pagination_store
    ).and_return(pagination_runtime)
    expect(pagination_runtime).to receive(:build_full_map).with(dimensions: [80, 24]).and_yield(1, 2)

    service.prepare_reader_launch(
      path: '/books/a.epub',
      load_document: ->(_path, _progress_reporter) { document },
      register_document: ->(_document) {},
      update_total_chapters: ->(_document) {},
      presenter: progress_presenter
    )

    expect(progress_presenter).to have_received(:update_message).with('Calculating pages...')
    # Pagination fills the [LOAD_PROGRESS_SHARE, 1.0] segment of the single
    # launch-wide bar: half of it built maps to 85%.
    expect(progress_presenter).to have_received(:update_status).with(message: nil, progress: be_within(0.001).of(0.85))
    expect(progress_presenter).to have_received(:update_status).with(progress: 1.0)
  end

  it 'scales document load progress into the load segment of the bar' do
    document = instance_double(Shoko::Application::Models::ReaderDocument, cached?: false)
    allow(pagination_runtime).to receive(:build_full_map)

    service.prepare_reader_launch(
      path: '/books/a.epub',
      load_document: lambda do |_path, progress_reporter|
        progress_reporter.update_status(message: 'Importing book...', progress: 1.0)
        document
      end,
      register_document: ->(_document) {},
      update_total_chapters: ->(_document) {},
      presenter: progress_presenter
    )

    # A fully loaded document is only LOAD_PROGRESS_SHARE of the launch:
    # pagination still has to run, so the bar must not claim 100% yet.
    expect(progress_presenter).to have_received(:update_status)
      .with(message: 'Importing book...', progress: be_within(0.001).of(0.7))
  end

  it 'reports 100% for cached documents only after the cache preload step' do
    document = instance_double(Shoko::Application::Models::ReaderDocument, cached?: true)

    service.prepare_reader_launch(
      path: '/books/a.cache',
      load_document: ->(_path, _progress_reporter) { document },
      register_document: ->(_document) {},
      update_total_chapters: ->(_document) {},
      presenter: progress_presenter
    )

    expect(progress_presenter).to have_received(:update_status).with(progress: 1.0)
  end
end
