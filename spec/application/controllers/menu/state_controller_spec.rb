# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'spec_helper'

RSpec.describe Shoko::Application::Controllers::Menu::StateController do
  class DummyState
    attr_reader :dispatched

    def initialize
      @dispatched = []
    end

    def dispatch(action)
      @dispatched << action
    end

    def get(_path)
      nil
    end
  end

  class FakeDependencies
    def initialize
      @store = {}
    end

    def register(name, value)
      @store[name] = value
    end

    def resolve(name)
      return @store[name] if @store.key?(name)

      raise KeyError, "Missing dependency: #{name}"
    end

    def registered?(name)
      @store.key?(name)
    end
  end

  let(:state) { DummyState.new }
  let(:deps) { FakeDependencies.new }
  let(:terminal_service) { instance_double('TerminalService', size: [24, 80]) }
  let(:frame_coordinator) { instance_double('FrameCoordinator') }
  let(:catalog) { instance_double('Catalog') }
  let(:state_writer) { instance_double('StateWriter', update_pagination_state: nil) }
  let(:clock) { instance_double('Clock', monotonic_now: 1.0) }
  let(:pagination_orchestrator) { instance_double('PaginationOrchestrator') }

  def build_menu
    Struct.new(:state, :container, :terminal_service, :frame_coordinator, :catalog).new(
      state, deps, terminal_service, frame_coordinator, catalog
    )
  end

  def register_minimum_dependencies
    deps.register(:terminal_service, terminal_service)
    deps.register(:progress_repository, instance_double('ProgressRepository', save_for_book: nil, find_by_book_path: nil))
    deps.register(:bookmark_repository, instance_double('BookmarkRepository', find_by_book_path: [], add_for_book: nil, delete_for_book: nil))
  end

  around do |example|
    Dir.mktmpdir('shoko-spec') do |dir|
      @tmp_dir = dir
      example.run
    end
  end

  def temp_epub(name)
    path = File.join(@tmp_dir, name)
    File.write(path, '')
    path
  end

  it 'reuses the cached document when the path matches' do
    register_minimum_dependencies
    path = temp_epub('a.epub')
    existing = instance_double('Document', canonical_path: path, chapter_count: 1)

    factory = instance_double('DocumentFactory')

    controller = described_class.new(
      build_menu,
      pagination_orchestrator: pagination_orchestrator,
      document: existing,
      document_service_factory: factory,
      state_writer: state_writer,
      clock: clock
    )

    expect(factory).not_to receive(:call)
    result = controller.send(:ensure_reader_document_for, path)

    expect(result).to be(true)
  end

  it 'reloads the document when the path changes' do
    register_minimum_dependencies
    path_a = temp_epub('a.epub')
    path_b = temp_epub('b.epub')

    existing = instance_double('Document', canonical_path: path_a, chapter_count: 1)

    new_doc = instance_double('Document', canonical_path: path_b, chapter_count: 2)
    service = instance_double('DocumentService', load_document: new_doc)
    factory = instance_double('DocumentFactory')

    controller = described_class.new(
      build_menu,
      pagination_orchestrator: pagination_orchestrator,
      document: existing,
      document_service_factory: factory,
      state_writer: state_writer,
      clock: clock
    )

    expect(factory).to receive(:call).with(path_b, progress_reporter: nil, background_worker: nil).and_return(service)

    result = controller.send(:ensure_reader_document_for, path_b)

    expect(result).to be(true)
    session_context = controller.instance_variable_get(:@reader_session_context)
    expect(session_context.document).to eq(new_doc)
  end

  it 'loads canonical source path when given a cache pointer path' do
    register_minimum_dependencies
    source_path = temp_epub('book.epub')
    pointer_path = temp_epub('book.cache')

    payload = Struct.new(:source_path).new(source_path)
    resolver = instance_double('CachePointerResolver', cache_pointer?: true, read_cache: payload)

    new_doc = instance_double('Document', canonical_path: source_path, chapter_count: 2)
    service = instance_double('DocumentService', load_document: new_doc)
    factory = instance_double('DocumentFactory')

    controller = described_class.new(
      build_menu,
      pagination_orchestrator: pagination_orchestrator,
      cache_pointer_resolver: resolver,
      document_service_factory: factory,
      state_writer: state_writer,
      clock: clock
    )

    expect(factory).to receive(:call).with(source_path, progress_reporter: nil, background_worker: nil)
                                       .and_return(service)

    result = controller.send(:ensure_reader_document_for, pointer_path)

    expect(result).to be(true)
    session_context = controller.instance_variable_get(:@reader_session_context)
    expect(session_context.document).to eq(new_doc)
  end
end
