# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::CacheImportAdapter do
  def build_progress_collector
    Struct.new(:events) do
      def update_status(message: nil, progress: nil)
        events << { message: message, progress: progress }
      end
    end.new([])
  end

  let(:document_loader) do
    Class.new do
      include Shoko::Core::Ports::Outbound::DocumentLoader

      def load(path:, progress_reporter: nil, background_worker: nil); end
    end.new
  end
  let(:document_warmup) { instance_double('DocumentWarmup', warm: :warmed) }

  it 'returns :skipped when document is already cached' do
    document = instance_double('Document', cached?: true)
    allow(document_loader).to receive(:load).with(path: '/books/a.epub', progress_reporter: nil, background_worker: nil)
                                            .and_return(document)

    adapter = described_class.new(document_loader: document_loader, document_warmup: document_warmup)

    expect(document_warmup).to receive(:warm).with(document)
    expect(adapter.import('/books/a.epub')).to eq(:skipped)
  end

  it 'returns :imported when document is newly built' do
    document = instance_double('Document', cached?: false)
    allow(document_loader).to receive(:load).with(path: '/books/a.epub', progress_reporter: nil, background_worker: nil)
                                            .and_return(document)

    adapter = described_class.new(document_loader: document_loader, document_warmup: document_warmup)

    expect(document_warmup).to receive(:warm).with(document)
    expect(adapter.import('/books/a.epub')).to eq(:imported)
  end

  it 'supports import without a warmup collaborator' do
    document = instance_double('Document', cached?: false)
    allow(document_loader).to receive(:load).with(path: '/books/a.epub', progress_reporter: nil, background_worker: nil)
                                            .and_return(document)

    adapter = described_class.new(document_loader: document_loader)

    expect(adapter.import('/books/a.epub')).to eq(:imported)
  end

  it 'warms imported documents with reader view state during the batch import path' do
    document = instance_double('Document', cached?: false, canonical_path: '/books/a.epub')
    allow(document_loader).to receive(:load).with(path: '/books/a.epub', progress_reporter: nil, background_worker: nil)
                                            .and_return(document)
    page_calculator = instance_double('PageCalculator', reset_session!: nil, build_dynamic_map!: { total_pages: 42 })
    warmup = Shoko::Application::Workflows::Cli::FolderImportReadinessWarmup.new(
      deps: Shoko::Application::Workflows::Cli::FolderImportReadinessWarmup::Dependencies.new(
        page_calculator: page_calculator,
        app_config_store: instance_double('AppConfigStore', load: instance_double('Config', page_numbering_mode: :dynamic)),
        reader_view_state_store: instance_double(
          'ReaderViewStateStore',
          load: Shoko::Core::Models::Session::ReaderViewStateSnapshot.build(sidebar_visible: true)
        ),
        reader_runtime_context: instance_double(
          'ReaderRuntimeContext',
          terminal_size: Shoko::Core::Models::Session::TerminalSize.build(width: 90, height: 32)
        ),
        logger: instance_double('Logger', debug: nil)
      )
    )
    adapter = described_class.new(document_loader: document_loader, document_warmup: warmup)

    expect(page_calculator).to receive(:build_dynamic_map!).with(
      90,
      32,
      document,
      config_reader: have_attributes(page_numbering_mode: :dynamic),
      sidebar_visible: true
    )

    expect(adapter.import('/books/a.epub')).to eq(:imported)
  end

  it 'forwards progress through load and warmup stages without regressing overall progress' do
    collector = build_progress_collector
    document = instance_double('Document', cached?: false)
    loader = Class.new do
      include Shoko::Core::Ports::Outbound::DocumentLoader

      attr_reader :reporters

      def initialize(document)
        @document = document
        @reporters = []
      end

      def load(path: nil, progress_reporter: nil, background_worker: nil)
        _ = path
        _ = background_worker
        @reporters << progress_reporter
        progress_reporter&.update_status(message: 'Loading cache...', progress: 0.5)
        @document
      end
    end.new(document)
    warmup = Class.new do
      attr_reader :reporters

      def initialize
        @reporters = []
      end

      def warm(document, progress_reporter: nil)
        @reporters << [document, progress_reporter]
        progress_reporter&.update_status(message: 'Warming pagination cache...', progress: 0.5)
        :warmed
      end
    end.new
    adapter = described_class.new(document_loader: loader, document_warmup: warmup)

    expect(adapter.import('/books/a.epub', progress_reporter: collector)).to eq(:imported)
    expect(loader.reporters.first).not_to be_nil
    expect(warmup.reporters.first.first).to eq(document)
    expect(warmup.reporters.first.last).not_to be_nil
    expect(collector.events).to eq(
      [
        { message: 'Loading cache...', progress: 0.425 },
        { message: 'Warming pagination cache...', progress: 0.925 },
        { message: 'Imported a.epub', progress: 1.0 },
      ]
    )
  end

  it 'keeps compatibility with warmup collaborators that do not accept a progress reporter keyword' do
    document = instance_double('Document', cached?: false)
    allow(document_loader).to receive(:load).with(path: '/books/a.epub', progress_reporter: nil, background_worker: nil)
                                            .and_return(document)
    legacy_warmup = Class.new do
      attr_reader :documents

      def initialize
        @documents = []
      end

      def warm(document)
        @documents << document
        :warmed
      end
    end.new
    adapter = described_class.new(document_loader: document_loader, document_warmup: legacy_warmup)

    expect(adapter.import('/books/a.epub')).to eq(:imported)
    expect(legacy_warmup.documents).to eq([document])
  end

  it 'raises a file-scoped parse error when the document loader returns nil' do
    allow(document_loader).to receive(:load).with(path: '/books/a.epub', progress_reporter: nil, background_worker: nil)
                                            .and_return(nil)

    adapter = described_class.new(document_loader: document_loader)

    expect { adapter.import('/books/a.epub') }
      .to raise_error(Shoko::BookParseError, 'Malformed book input at /books/a.epub: document import returned nil')
  end

  it 'propagates BookParseError when the document service raises malformed-book input' do
    allow(document_loader).to receive(:load).with(path: '/books/bad.epub', progress_reporter: nil, background_worker: nil)
                                            .and_raise(Shoko::BookParseError.new('bad book', '/books/bad.epub'))

    adapter = described_class.new(document_loader: document_loader)

    expect { adapter.import('/books/bad.epub') }
      .to raise_error(Shoko::BookParseError, /bad book/)
  end

  it 'propagates importer failures for workflow-level aggregation' do
    allow(document_loader).to receive(:load).and_raise(StandardError, 'boom')

    adapter = described_class.new(document_loader: document_loader)

    expect { adapter.import('/books/a.epub') }.to raise_error(StandardError, 'boom')
  end
end
