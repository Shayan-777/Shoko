# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::ReaderLaunch::ProgressOrchestration do
  class ReaderLaunchProgressOrchestrationTestMenuSessionStore
    include Shoko::Core::Ports::Outbound::MenuSessionStore

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
      Shoko::Core::Models::Session::MenuSessionSnapshot.build(browse_selected: 0, mode: :browse)
    )
  end
  let(:progress_presenter) do
    instance_double(
      'ProgressPresenter',
      show: nil,
      clear: nil,
      update_status: false,
      update_message: nil,
      update: nil
    )
  end
  let(:progress_presenters) { instance_double('ProgressPresenters', build: progress_presenter) }
  let(:null_presenter) { instance_double('NullPresenter') }
  let(:pagination_runtime) { instance_double('PaginationRuntime', build_full_map: nil) }
  let(:pagination_orchestrator) { instance_double('PaginationOrchestrator', bind: pagination_runtime) }
  let(:page_calculator) { instance_double('PageCalculator') }
  let(:app_config_store) { instance_double('AppConfigStore') }
  let(:reader_session_store) { instance_double('ReaderSessionStore') }
  let(:reader_view_state_store) { instance_double('ReaderViewStateStore') }
  let(:reader_pagination_store) { instance_double('ReaderPaginationStore') }
  let(:reader_runtime_context) do
    instance_double(
      'ReaderRuntimeContext',
      terminal_size: Shoko::Core::Models::Session::TerminalSize.build(width: 80, height: 24)
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

  it 'binds the full pagination runtime contract during pagination build' do
    document = instance_double('Document', cached?: false)

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
    expect(progress_presenter).to have_received(:update).with(done: 1, total: 2)
    expect(progress_presenter).to have_received(:update).with(done: 1, total: 1)
  end
end
