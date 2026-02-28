# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::ReaderLaunchService do
  class PortCatalogDouble
    attr_accessor :scan_message, :scan_status

    def update_scan_state(status:, message:)
      @scan_status = status
      @scan_message = message
    end
  end

  class PortMenuRuntimeDouble
    include Shoko::Core::Ports::Outbound::MenuReaderRuntime

    def draw_screen; end

    def switch_mode(_mode); end

    def run_reader(path:, preloaded_document:, background_worker:); end
  end

  class PortBookSelectionDouble
    include Shoko::Core::Ports::Outbound::MenuBookSelection

    attr_accessor :selected_book_value, :filtered_books_value

    def initialize
      @selected_book_value = nil
      @filtered_books_value = []
    end

    def selected_book
      @selected_book_value
    end

    def filtered_books
      @filtered_books_value
    end
  end

  class PortMenuWorkflowStateReaderDouble
    include Shoko::Core::Ports::Outbound::MenuWorkflowStateReader

    attr_accessor :selected_library_index_value, :current_menu_mode_value,
                  :selected_annotation_record_value, :selected_annotation_book_path_value,
                  :annotation_editor_text_value, :dictionary_entries_value

    def initialize
      @selected_library_index_value = 0
      @current_menu_mode_value = :browse
      @selected_annotation_record_value = nil
      @selected_annotation_book_path_value = nil
      @annotation_editor_text_value = ''
      @dictionary_entries_value = []
    end

    def selected_library_index
      @selected_library_index_value
    end

    def current_menu_mode
      @current_menu_mode_value
    end

    def selected_annotation_record
      @selected_annotation_record_value
    end

    def selected_annotation_book_path
      @selected_annotation_book_path_value
    end

    def annotation_editor_text
      @annotation_editor_text_value
    end

    def dictionary_entries
      @dictionary_entries_value
    end
  end

  class PortProgressPresentersDouble
    include Shoko::Core::Ports::Outbound::MenuProgressPresenters

    def initialize(presenter)
      @presenter = presenter
    end

    def build
      @presenter
    end
  end

  let(:menu_state_reader) { PortMenuWorkflowStateReaderDouble.new }
  let(:reader_state_reader) { instance_double('ReaderStateReader', running?: true) }
  let(:state_writer) { instance_double('StateWriter', update_pagination_state: nil, update_reader_meta: nil, update_reader: nil) }
  let(:reader_session_context) { Shoko::Bootstrap::ReaderSessionContext.new }
  let(:menu_session_context) { Shoko::Bootstrap::MenuSessionContext.new }
  let(:pagination_orchestrator) { instance_double('PaginationOrchestrator') }
  let(:catalog) { PortCatalogDouble.new }
  let(:logger) { instance_double('Logger', error: nil, debug: nil) }
  let(:terminal_service) { instance_double('TerminalService') }
  let(:menu_runtime) { PortMenuRuntimeDouble.new }
  let(:book_selection) { PortBookSelectionDouble.new }
  let(:clock) { instance_double('Clock', monotonic_now: 1.0) }
  let(:path_ops) do
    Class.new do
      def expand_path(path)
        File.expand_path(path)
      end
    end.new
  end
  let(:file_probe) { instance_double('FileProbe', exist?: true, file?: true) }
  let(:progress_presenter) do
    instance_double(
      'ProgressPresenter',
      show: nil,
      update: nil,
      update_message: nil,
      update_status: false,
      set_progress: nil,
      clear: nil
    )
  end
  let(:document_service_factory) { instance_double('DocumentServiceFactory') }
  let(:progress_presenters) { PortProgressPresentersDouble.new(progress_presenter) }

  def build_service(overrides = {})
    deps = described_class::Dependencies.new(
      menu_state_reader: menu_state_reader,
      reader_state_reader: reader_state_reader,
      state_writer: state_writer,
      runtime_config: nil,
      reader_session_context: reader_session_context,
      menu_session_context: menu_session_context,
      page_calculator: nil,
      pagination_orchestrator: pagination_orchestrator,
      pagination_cache_preloader: nil,
      document_service_factory: document_service_factory,
      config_reader: nil,
      background_worker_factory: nil,
      recent_files_repository: nil,
      cache_pointer_resolver: nil,
      document_path_resolver: nil,
      logger: logger,
      terminal_service: terminal_service,
      catalog: catalog,
      menu_runtime: menu_runtime,
      book_selection: book_selection,
      progress_presenters: progress_presenters,
      file_probe: file_probe,
      path_ops: path_ops,
      clock: clock,
      **overrides
    ).validate!
    described_class.new(deps: deps)
  end

  it 'reuses cached document when canonical path matches' do
    path = '/tmp/book.epub'
    existing = instance_double('Document', canonical_path: path)
    reader_session_context.document = existing

    service = build_service

    expect(document_service_factory).not_to receive(:call)
    expect(state_writer).not_to receive(:update_pagination_state)
    expect(service.ensure_reader_document_for(path)).to be(true)
  end

  it 'reloads document when target path differs and updates session state' do
    path_a = '/tmp/a.epub'
    path_b = '/tmp/b.epub'
    existing = instance_double('Document', canonical_path: path_a)
    reader_session_context.document = existing

    loaded_document = instance_double('Document', canonical_path: path_b, chapter_count: 9)
    loader = instance_double('DocumentService', load_document: loaded_document)

    service = build_service

    expect(document_service_factory)
      .to receive(:call)
      .with(path_b, progress_reporter: nil, background_worker: nil)
      .and_return(loader)
    expect(state_writer).to receive(:update_pagination_state).with(total_chapters: 9)

    expect(service.ensure_reader_document_for(path_b)).to be(true)
    expect(reader_session_context.document).to eq(loaded_document)
  end

  it 'resolves cache-pointer paths to source path before loading document' do
    pointer_path = '/tmp/book.cache'
    source_path = '/tmp/book.epub'
    payload = Struct.new(:source_path).new(source_path)
    resolver = instance_double('CachePointerResolver')
    loaded_document = instance_double('Document', canonical_path: source_path, chapter_count: 3)
    loader = instance_double('DocumentService', load_document: loaded_document)

    service = build_service(cache_pointer_resolver: resolver)

    expect(resolver).to receive(:cache_pointer?).with(pointer_path).and_return(true)
    expect(resolver).to receive(:read_cache).with(pointer_path, strict: false).and_return(payload)
    expect(document_service_factory)
      .to receive(:call)
      .with(source_path, progress_reporter: nil, background_worker: nil)
      .and_return(loader)
    expect(state_writer).to receive(:update_pagination_state).with(total_chapters: 3)

    expect(service.ensure_reader_document_for(pointer_path)).to be(true)
    expect(reader_session_context.document).to eq(loaded_document)
  end

  it 'returns false and updates catalog error state when document load fails' do
    failing_factory = lambda do |_path, **_kwargs|
      raise StandardError, 'load failed'
    end
    service = build_service(document_service_factory: failing_factory)

    expect(state_writer).not_to receive(:update_pagination_state)

    expect(service.ensure_reader_document_for('/tmp/bad.epub')).to be(false)
    expect(catalog.scan_status).to eq(:error)
    expect(catalog.scan_message).to include('Failed: StandardError: load failed')
    expect(reader_session_context.document).to be_nil
  end

  it 'builds background worker with logger and name when factory supports both keywords' do
    worker = instance_double('BackgroundWorker')
    logger_double = logger
    factory = lambda do |logger:, name:|
      expect(logger).to be(logger_double)
      expect(name).to eq('document-preload')
      worker
    end
    service = build_service(background_worker_factory: factory)

    built = service.send(:build_background_worker, name: 'document-preload')
    expect(built).to be(worker)
  end

  it 'falls back to name-only factory signature for backward compatibility' do
    worker = instance_double('BackgroundWorker')
    factory = lambda do |name:|
      expect(name).to eq('document-preload')
      worker
    end
    service = build_service(background_worker_factory: factory)

    built = service.send(:build_background_worker, name: 'document-preload')
    expect(built).to be(worker)
  end
end
