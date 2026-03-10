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
      Shoko::Core::Models::Session::MenuSnapshot.build(browse_selected: 0, mode: :browse)
    )
  end
  let(:menu_runtime) { instance_double('MenuRuntime', draw_screen: nil) }
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
  let(:pagination_session) { instance_double('PaginationSession', build_full_map!: nil) }
  let(:pagination_orchestrator) { instance_double('PaginationOrchestrator', session: pagination_session) }
  let(:reader_runtime_context) do
    instance_double(
      'ReaderRuntimeContext',
      terminal_size: Shoko::Core::Models::Session::TerminalSize.build(width: 80, height: 24)
    )
  end
  let(:clock) { instance_double('Clock', monotonic_now: 1.0) }

  subject(:service) do
    described_class.new(
      deps: described_class::Dependencies.new(
        menu_session_store: menu_session_store,
        menu_runtime: menu_runtime,
        progress_presenters: progress_presenters,
        null_presenter: null_presenter,
        pagination_orchestrator: pagination_orchestrator,
        page_calculator: instance_double('PageCalculator'),
        app_config_store: instance_double('AppConfigStore'),
        reader_session_store: instance_double('ReaderSessionStore'),
        pagination_cache_preloader: nil,
        runtime_config: nil,
        reader_runtime_context: reader_runtime_context,
        clock: clock,
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
end
