# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UnifiedApplication do
  let(:epub_path) { '/books/example.epub' }
  let(:app_mode_runner) { instance_double('AppModeRunner', run_reader: nil, run_menu: nil) }
  let(:terminal_session) { instance_double('TerminalSession', setup: nil, cleanup: nil) }
  let(:instrumentation) { instance_double('InstrumentationService', start_trace: nil, cancel_trace: nil) }
  let(:cache_availability) { instance_double('CacheAvailability', cache_available?: false) }
  let(:factory) { instance_double('DocumentServiceFactory') }
  let(:service) { instance_double('DocumentService') }
  let(:document) { instance_double('Document', cached?: false) }
  let(:presenter) { instance_double('CLIProgressPresenter', start: nil, update_status: nil, finish: nil) }
  let(:cli_progress_renderer) { instance_double('CLIProgressRenderer') }
  let(:page_calculator) { instance_double('PageCalculatorService') }
  let(:config_reader) { instance_double('ConfigReader', page_numbering_mode: :dynamic) }
  let(:state_writer) { instance_double('StateWriter') }
  let(:reader_state_reader) { instance_double('ReaderStateReader', pending_progress: nil, sidebar_visible?: false) }
  let(:instrumentation_port) { instance_double('Instrumentation', measure: nil) }
  let(:reader_session_context) { instance_double('ReaderSessionContext', document: nil, :'document=' => nil) }
  let(:logger) { instance_double('Logger', error: nil) }
  let(:deps) do
    described_class::Dependencies.new(
      app_mode_runner: app_mode_runner,
      terminal_session: terminal_session,
      instrumentation_service: instrumentation,
      cache_availability: cache_availability,
      document_service_factory: factory,
      cli_progress_renderer: cli_progress_renderer,
      page_calculator: page_calculator,
      config_reader: config_reader,
      state_writer: state_writer,
      reader_state_reader: reader_state_reader,
      reader_session_context: reader_session_context,
      instrumentation: instrumentation_port,
      logger: logger
    )
  end

  before do
    allow(terminal_session).to receive(:size).and_return([24, 80])
    allow(Shoko::Application::CLIProgressPresenter).to receive(:new)
      .with(renderer: cli_progress_renderer)
      .and_return(presenter)
    allow(factory).to receive(:call).and_return(service)
    allow(service).to receive(:load_document).and_return(document)
    allow(state_writer).to receive(:update_pagination_state)
    allow(state_writer).to receive(:update_page)
    allow(state_writer).to receive(:update_selections)
    allow(page_calculator).to receive(:build_dynamic_map!).and_return(
      { total_pages: 1, last_width: 80, last_height: 24 }
    )
    allow(page_calculator).to receive(:apply_pending_precise_restore!).and_return(
      { current_page_index: 0, clear_pending_progress: true }
    )
  end

  it 'preloads document before entering the terminal when cache is missing' do
    expect(instrumentation).to receive(:start_trace).with(epub_path).ordered
    expect(presenter).to receive(:start).ordered
    expect(factory).to receive(:call).with(epub_path, progress_reporter: kind_of(Proc)).ordered.and_return(service)
    expect(service).to receive(:load_document).ordered.and_return(document)
    expect(reader_session_context).to receive(:document=).with(document).ordered
    expect(presenter).to receive(:update_status).with(message: 'Calculating pages...', progress: 0.0).ordered
    expect(instrumentation_port).to receive(:measure).with('pagination.build').ordered.and_yield
    expect(page_calculator).to receive(:build_dynamic_map!).ordered
      .with(80, 24, document, config_reader: config_reader, sidebar_visible: false)
      .and_yield(1, 1)
      .and_return({ total_pages: 1, last_width: 80, last_height: 24 })
    expect(presenter).to receive(:update_status).with(message: 'Calculating pages (1/1)...', progress: 1.0).ordered
    expect(state_writer).to receive(:update_pagination_state)
      .with(total_pages: 1, last_width: 80, last_height: 24).ordered
    expect(page_calculator).to receive(:apply_pending_precise_restore!)
      .with(reader_state_reader).ordered
      .and_return({ current_page_index: 0, clear_pending_progress: true })
    expect(state_writer).to receive(:update_page).with(current_page_index: 0).ordered
    expect(state_writer).to receive(:update_selections).with(pending_progress: nil).ordered
    expect(presenter).to receive(:finish).ordered
    expect(terminal_session).to receive(:setup).ordered
    expect(app_mode_runner).to receive(:run_reader).with(path: epub_path).ordered
    expect(terminal_session).to receive(:cleanup).ordered
    expect(instrumentation).to receive(:cancel_trace).ordered

    described_class.new(epub_path, deps: deps).run
  end

  it 'skips preload when cache is available' do
    allow(cache_availability).to receive(:cache_available?).and_return(true)

    expect(factory).not_to receive(:call)
    expect(Shoko::Application::CLIProgressPresenter).not_to receive(:new)
    expect(terminal_session).to receive(:setup)
    expect(app_mode_runner).to receive(:run_reader).with(path: epub_path)

    described_class.new(epub_path, deps: deps).run
  end
end
