# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UnifiedApplication do
  let(:epub_path) { '/books/example.epub' }
  let(:container) { instance_double('Container') }
  let(:terminal_service) { instance_double('TerminalService', setup: nil, cleanup: nil) }
  let(:instrumentation) { instance_double('InstrumentationService', start_trace: nil, cancel_trace: nil) }
  let(:cache_availability) { instance_double('CacheAvailability', cache_available?: false) }
  let(:factory) { instance_double('DocumentServiceFactory') }
  let(:service) { instance_double('DocumentService') }
  let(:document) { instance_double('Document', cached?: false) }
  let(:controller) { instance_double('ReaderController', run: nil) }
  let(:presenter) { instance_double('CLIProgressPresenter', start: nil, update_status: nil, finish: nil) }
  let(:page_calculator) { instance_double('PageCalculatorService') }
  let(:config_reader) { instance_double('ConfigReader', page_numbering_mode: :dynamic) }
  let(:state_writer) { instance_double('StateWriter') }
  let(:reader_state_reader) { instance_double('ReaderStateReader', pending_progress: nil) }
  let(:instrumentation_port) { instance_double('Instrumentation', measure: nil) }

  before do
    allow(Shoko::Application::ContainerFactory).to receive(:create_default_container).and_return(container)
    allow(Shoko::Application::ContainerFactory).to receive(:build_reader_controller).and_return(controller)
    allow(container).to receive(:resolve).with(:terminal_service).and_return(terminal_service)
    allow(terminal_service).to receive(:size).and_return([24, 80])
    allow(container).to receive(:resolve_optional).with(:instrumentation_service).and_return(instrumentation)
    allow(container).to receive(:resolve_optional).with(:instrumentation).and_return(instrumentation_port)
    allow(container).to receive(:resolve_optional).with(:cache_availability).and_return(cache_availability)
    allow(container).to receive(:resolve_optional).with(:document_service_factory).and_return(factory)
    allow(container).to receive(:resolve_optional).with(:page_calculator).and_return(page_calculator)
    allow(container).to receive(:resolve_optional).with(:config_reader).and_return(config_reader)
    allow(container).to receive(:resolve_optional).with(:state_writer).and_return(state_writer)
    allow(container).to receive(:resolve_optional).with(:reader_state_reader).and_return(reader_state_reader)
    allow(container).to receive(:register)
    allow(Shoko::Application::CLIProgressPresenter).to receive(:new).and_return(presenter)
    allow(factory).to receive(:call).and_return(service)
    allow(service).to receive(:load_document).and_return(document)
    allow(page_calculator).to receive(:build_dynamic_map!)
    allow(page_calculator).to receive(:apply_pending_precise_restore!)
  end

  it 'preloads document before entering the terminal when cache is missing' do
    expect(instrumentation).to receive(:start_trace).with(epub_path).ordered
    expect(presenter).to receive(:start).ordered
    expect(factory).to receive(:call).with(epub_path, progress_reporter: kind_of(Proc)).ordered.and_return(service)
    expect(service).to receive(:load_document).ordered.and_return(document)
    expect(container).to receive(:register).with(:document, document).ordered
    expect(presenter).to receive(:update_status).with(message: 'Calculating pages...', progress: 0.0).ordered
    expect(instrumentation_port).to receive(:measure).with('pagination.build').ordered.and_yield
    expect(page_calculator).to receive(:build_dynamic_map!).ordered
      .with(80, 24, document, state_writer: state_writer, config_reader: config_reader)
      .and_yield(1, 1)
    expect(presenter).to receive(:update_status).with(message: 'Calculating pages (1/1)...', progress: 1.0).ordered
    expect(page_calculator).to receive(:apply_pending_precise_restore!)
      .with(reader_state_reader, state_writer: state_writer).ordered
    expect(presenter).to receive(:finish).ordered
    expect(terminal_service).to receive(:setup).ordered
    expect(Shoko::Application::ContainerFactory).to receive(:build_reader_controller).with(container, epub_path).ordered.and_return(controller)
    expect(controller).to receive(:run).ordered
    expect(terminal_service).to receive(:cleanup).ordered
    expect(instrumentation).to receive(:cancel_trace).ordered

    described_class.new(epub_path).run
  end

  it 'skips preload when cache is available' do
    allow(cache_availability).to receive(:cache_available?).and_return(true)

    expect(factory).not_to receive(:call)
    expect(Shoko::Application::CLIProgressPresenter).not_to receive(:new)
    expect(terminal_service).to receive(:setup)
    expect(controller).to receive(:run)

    described_class.new(epub_path).run
  end
end
