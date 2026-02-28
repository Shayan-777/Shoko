# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::ReaderLaunch::ProgressOrchestration do
  let(:menu_state_reader) { instance_double('MenuStateReader', selected_library_index: 0, current_menu_mode: :browse) }
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
  let(:ui_state_reader) { instance_double('UiStateReader', terminal_width: 80, terminal_height: 24) }
  let(:clock) { instance_double('Clock', monotonic_now: 1.0) }

  subject(:service) do
    described_class.new(
      deps: described_class::Dependencies.new(
        menu_state_reader: menu_state_reader,
        menu_runtime: menu_runtime,
        progress_presenters: progress_presenters,
        null_presenter: null_presenter,
        pagination_orchestrator: pagination_orchestrator,
        page_calculator: instance_double('PageCalculator'),
        config_reader: instance_double('ConfigReader'),
        reader_state_reader: instance_double('ReaderStateReader'),
        sidebar_state_reader: instance_double('SidebarStateReader', sidebar_visible?: false),
        state_writer: instance_double('StateWriter'),
        pagination_cache_preloader: nil,
        runtime_config: nil,
        ui_state_reader: ui_state_reader,
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
