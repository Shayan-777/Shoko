# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::ReaderModeRunner do
  let(:epub_path) { '/books/example.epub' }
  let(:reader_controller) { instance_double('ReaderController', run: nil) }
  let(:build_reader_controller) { instance_double('ReaderControllerBuilder', call: reader_controller) }
  let(:terminal_session) { instance_double('TerminalSession', setup: nil, cleanup: nil) }
  let(:instrumentation_service) { instance_double('InstrumentationService', start_trace: nil, cancel_trace: nil) }
  let(:cache_availability) { instance_double('CacheAvailability', cache_available?: false) }
  let(:document_loader) do
    Class.new do
      include Shoko::Core::Ports::Outbound::DocumentLoader

      def load(path:, progress_reporter: nil, background_worker: nil); end
    end.new
  end
  let(:document) { instance_double('Document', cached?: false) }
  let(:presenter) { instance_double('CLIProgressPresenter', start: nil, update_status: nil, finish: nil) }
  let(:cli_progress_renderer) { instance_double('CLIProgressRenderer') }
  let(:page_calculator) { instance_double('PageCalculatorService') }
  let(:config_snapshot) { Shoko::Core::Models::Session::ConfigSnapshot.build(page_numbering_mode: :dynamic) }
  let(:reader_snapshot) { Shoko::Core::Models::Session::ReaderSnapshot.build(pending_progress: nil, sidebar_visible: false) }
  let(:app_config_store) { instance_double('AppConfigStore', load: config_snapshot) }
  let(:reader_session_store) { instance_double('ReaderSessionStore', load: reader_snapshot) }
  let(:terminal_size) { Shoko::Core::Models::Session::TerminalSize.build(width: 80, height: 24) }
  let(:reader_runtime_context) { instance_double('ReaderRuntimeContext', terminal_size: terminal_size) }
  let(:instrumentation_port) { instance_double('Instrumentation', measure: nil) }
  let(:reader_launch_state) { instance_double('ReaderLaunchState', set_preloaded_document: nil) }
  let(:logger) { instance_double('Logger', error: nil) }

  subject(:runner) do
    described_class.new(
      build_reader_controller: build_reader_controller,
      terminal_session: terminal_session,
      instrumentation_service: instrumentation_service,
      cache_availability: cache_availability,
      document_loader: document_loader,
      cli_progress_renderer: cli_progress_renderer,
      page_calculator: page_calculator,
      app_config_store: app_config_store,
      reader_session_store: reader_session_store,
      reader_runtime_context: reader_runtime_context,
      reader_launch_state: reader_launch_state,
      instrumentation: instrumentation_port,
      logger: logger
    )
  end

  before do
    allow(Shoko::Adapters::Runtime::CLIProgressPresenter).to receive(:new)
      .with(renderer: cli_progress_renderer)
      .and_return(presenter)
    allow(document_loader).to receive(:load).and_return(document)
    allow(reader_session_store).to receive(:save) { |snapshot| snapshot }
    allow(page_calculator).to receive(:build_dynamic_map!).and_return(
      { total_pages: 1, last_width: 80, last_height: 24 }
    )
    allow(page_calculator).to receive(:apply_pending_precise_restore!).and_return(
      { current_page_index: 0, clear_pending_progress: true }
    )
  end

  it 'preloads document before entering the terminal when cache is missing' do
    expect(instrumentation_service).to receive(:start_trace).with(epub_path).ordered
    expect(presenter).to receive(:start).ordered
    expect(document_loader).to receive(:load).with(path: epub_path, progress_reporter: kind_of(Object)).ordered
                                             .and_return(document)
    expect(reader_launch_state).to receive(:set_preloaded_document).with(document).ordered
    expect(presenter).to receive(:update_status).with(message: 'Calculating pages...', progress: 0.0).ordered
    expect(instrumentation_port).to receive(:measure).with('pagination.build').ordered.and_yield
    expect(page_calculator).to receive(:build_dynamic_map!).ordered
                                                           .with(80, 24, document, config_reader: config_snapshot, sidebar_visible: false)
                                                           .and_yield(1, 1)
                                                           .and_return({ total_pages: 1, last_width: 80, last_height: 24 })
    expect(presenter).to receive(:update_status).with(message: 'Calculating pages (1/1)...', progress: 1.0).ordered
    expect(reader_session_store).to receive(:save).ordered
                                                  .with(have_attributes(total_pages: 1, last_width: 80, last_height: 24))
                                                  .and_return(reader_snapshot.with(total_pages: 1, last_width: 80, last_height: 24))
    expect(page_calculator).to receive(:apply_pending_precise_restore!)
      .with(have_attributes(total_pages: 1, last_width: 80, last_height: 24)).ordered
      .and_return({ current_page_index: 0, clear_pending_progress: true })
    expect(reader_session_store).to receive(:save).ordered
                                                  .with(have_attributes(current_page_index: 0, pending_progress: nil))
    expect(presenter).to receive(:finish).ordered
    expect(terminal_session).to receive(:setup).ordered
    expect(build_reader_controller).to receive(:call).with(epub_path).ordered.and_return(reader_controller)
    expect(reader_controller).to receive(:run).ordered
    expect(terminal_session).to receive(:cleanup).ordered
    expect(instrumentation_service).to receive(:cancel_trace).ordered

    runner.run(path: epub_path)
  end

  it 'skips preload when cache is available' do
    allow(cache_availability).to receive(:cache_available?).and_return(true)

    expect(document_loader).not_to receive(:load)
    expect(Shoko::Adapters::Runtime::CLIProgressPresenter).not_to receive(:new)
    expect(terminal_session).to receive(:setup)
    expect(build_reader_controller).to receive(:call).with(epub_path).and_return(reader_controller)
    expect(reader_controller).to receive(:run)

    runner.run(path: epub_path)
  end
end
